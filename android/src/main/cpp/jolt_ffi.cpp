#include <Jolt/Jolt.h>

#include <Jolt/Core/Factory.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/Collision/Shape/CapsuleShape.h>
#include <Jolt/Physics/Collision/Shape/CylinderShape.h>
#include <Jolt/Physics/Collision/Shape/SphereShape.h>
#include <Jolt/Physics/Collision/Shape/StaticCompoundShape.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <thread>
#include <vector>

using namespace JPH;

namespace {

namespace Layers {
constexpr ObjectLayer kStatic = 0;
constexpr ObjectLayer kMoving = 1;
constexpr uint kCount = 2;
}  // namespace Layers

namespace BroadPhaseLayers {
constexpr BroadPhaseLayer kStatic(0);
constexpr BroadPhaseLayer kMoving(1);
constexpr uint kCount = 2;
}  // namespace BroadPhaseLayers

class BroadPhaseLayerInterfaceImpl final : public BroadPhaseLayerInterface {
 public:
  BroadPhaseLayerInterfaceImpl() {
    layers_[Layers::kStatic] = BroadPhaseLayers::kStatic;
    layers_[Layers::kMoving] = BroadPhaseLayers::kMoving;
  }

  uint GetNumBroadPhaseLayers() const override { return BroadPhaseLayers::kCount; }

  BroadPhaseLayer GetBroadPhaseLayer(ObjectLayer layer) const override {
    JPH_ASSERT(layer < Layers::kCount);
    return layers_[layer];
  }

 private:
  BroadPhaseLayer layers_[Layers::kCount];
};

class ObjectVsBroadPhaseLayerFilterImpl final
    : public ObjectVsBroadPhaseLayerFilter {
 public:
  bool ShouldCollide(ObjectLayer layer, BroadPhaseLayer broad_phase) const override {
    return layer == Layers::kMoving || broad_phase == BroadPhaseLayers::kMoving;
  }
};

class ObjectLayerPairFilterImpl final : public ObjectLayerPairFilter {
 public:
  bool ShouldCollide(ObjectLayer first, ObjectLayer second) const override {
    return first == Layers::kMoving || second == Layers::kMoving;
  }
};

std::mutex g_factory_mutex;
int g_world_count = 0;

void AcquireJolt() {
  std::lock_guard<std::mutex> lock(g_factory_mutex);
  if (g_world_count++ == 0) {
    RegisterDefaultAllocator();
    Factory::sInstance = new Factory();
    RegisterTypes();
  }
}

void ReleaseJolt() {
  std::lock_guard<std::mutex> lock(g_factory_mutex);
  if (--g_world_count == 0) {
    UnregisterTypes();
    delete Factory::sInstance;
    Factory::sInstance = nullptr;
  }
}

struct JoltLifetime {
  JoltLifetime() { AcquireJolt(); }
  ~JoltLifetime() { ReleaseJolt(); }
};

RefConst<Shape> CreateShape(int type, float a, float b, float c) {
  switch (type) {
    case 1:
      return new CapsuleShape(a, b);
    case 2:
      return new SphereShape(a);
    case 3:
      return new CylinderShape(a, b);
    default:
      return new BoxShape(Vec3(a, b, c));
  }
}

EMotionType ToMotionType(int type) {
  switch (type) {
    case 0:
      return EMotionType::Static;
    case 1:
      return EMotionType::Kinematic;
    default:
      return EMotionType::Dynamic;
  }
}

struct PhysicsWorld {
  PhysicsWorld()
      : temp_allocator(2 * 1024 * 1024),
        job_system(cMaxPhysicsJobs, cMaxPhysicsBarriers,
                   std::max(1u, std::thread::hardware_concurrency()) - 1) {
    physics.Init(1024, 0, 1024, 1024, broad_phase_layers,
                 object_vs_broad_phase_filter, object_layer_pair_filter);
  }

  ~PhysicsWorld() {
    BodyInterface &body_interface = physics.GetBodyInterface();
    for (const BodyID body_id : bodies) {
      body_interface.RemoveBody(body_id);
      body_interface.DestroyBody(body_id);
    }
  }

  uint32_t CreateBody(int shape_type, float shape_a, float shape_b,
                      float shape_c, int motion_type, float x, float y,
                      float z, float friction, float restitution,
                      bool is_sensor) {
    return CreateBodyFromShape(CreateShape(shape_type, shape_a, shape_b, shape_c),
                               motion_type, x, y, z, friction, restitution,
                               is_sensor);
  }

  uint32_t CreateCompoundBody(StaticCompoundShapeSettings *compound_settings,
                              int motion_type, float x, float y, float z,
                              float friction, float restitution,
                              bool is_sensor) {
    ShapeSettings::ShapeResult result = compound_settings->Create();
    if (result.HasError()) {
      return 0;
    }
    return CreateBodyFromShape(result.Get(), motion_type, x, y, z, friction,
                               restitution, is_sensor);
  }

  uint32_t CreateBodyFromShape(RefConst<Shape> shape, int motion_type, float x,
                               float y, float z, float friction,
                               float restitution, bool is_sensor) {
    const EMotionType motion = ToMotionType(motion_type);
    BodyCreationSettings settings(shape, RVec3(x, y, z), Quat::sIdentity(), motion,
        motion == EMotionType::Static ? Layers::kStatic : Layers::kMoving);
    settings.mFriction = friction;
    settings.mRestitution = restitution;
    settings.mIsSensor = is_sensor;
    BodyID body_id = physics.GetBodyInterface().CreateAndAddBody(
        settings, motion == EMotionType::Static ? EActivation::DontActivate
                                               : EActivation::Activate);
    bodies.push_back(body_id);
    return body_id.GetIndexAndSequenceNumber();
  }

  void DestroyBody(BodyID body_id) {
    BodyInterface &body_interface = physics.GetBodyInterface();
    body_interface.RemoveBody(body_id);
    body_interface.DestroyBody(body_id);
    bodies.erase(std::remove(bodies.begin(), bodies.end(), body_id),
                 bodies.end());
  }

  void Step(float delta_seconds) {
    const float delta = std::clamp(delta_seconds, 0.0f, 1.0f / 30.0f);
    if (delta > 0.0f) {
      physics.Update(delta, 1, &temp_allocator, &job_system);
    }
  }

  bool CastRay(float origin_x, float origin_y, float origin_z,
               float direction_x, float direction_y, float direction_z) {
    last_ray_hit.Reset();
    return physics.GetNarrowPhaseQuery().CastRay(
        RRayCast(RVec3(origin_x, origin_y, origin_z),
                 Vec3(direction_x, direction_y, direction_z)),
        last_ray_hit);
  }

  JoltLifetime lifetime;
  BroadPhaseLayerInterfaceImpl broad_phase_layers;
  ObjectVsBroadPhaseLayerFilterImpl object_vs_broad_phase_filter;
  ObjectLayerPairFilterImpl object_layer_pair_filter;
  TempAllocatorImpl temp_allocator;
  JobSystemThreadPool job_system;
  PhysicsSystem physics;
  std::vector<BodyID> bodies;
  RayCastResult last_ray_hit;
};

PhysicsWorld *WorldFromHandle(int64_t handle) {
  return reinterpret_cast<PhysicsWorld *>(handle);
}

BodyID BodyFromHandle(uint32_t handle) { return BodyID(handle); }

StaticCompoundShapeSettings *CompoundFromHandle(int64_t handle) {
  return reinterpret_cast<StaticCompoundShapeSettings *>(handle);
}

}  // namespace

#define JOLT_FFI_EXPORT extern "C" __attribute__((visibility("default"))) \
    __attribute__((used))

JOLT_FFI_EXPORT int64_t jolt_world_create() {
  return reinterpret_cast<int64_t>(new PhysicsWorld());
}

JOLT_FFI_EXPORT void jolt_world_destroy(int64_t world) {
  delete WorldFromHandle(world);
}

JOLT_FFI_EXPORT void jolt_world_step(int64_t world, float delta_seconds) {
  WorldFromHandle(world)->Step(delta_seconds);
}

JOLT_FFI_EXPORT bool jolt_world_cast_ray(int64_t world, float origin_x,
                                         float origin_y, float origin_z,
                                         float direction_x, float direction_y,
                                         float direction_z) {
  return WorldFromHandle(world)->CastRay(origin_x, origin_y, origin_z,
                                         direction_x, direction_y,
                                         direction_z);
}

JOLT_FFI_EXPORT uint32_t jolt_world_ray_hit_body(int64_t world) {
  return WorldFromHandle(world)->last_ray_hit.mBodyID
      .GetIndexAndSequenceNumber();
}

JOLT_FFI_EXPORT float jolt_world_ray_hit_fraction(int64_t world) {
  return WorldFromHandle(world)->last_ray_hit.mFraction;
}

JOLT_FFI_EXPORT uint32_t jolt_body_create(
    int64_t world, int shape_type, float shape_a, float shape_b, float shape_c,
    int motion_type, float x, float y, float z, float friction,
    float restitution, bool is_sensor) {
  return WorldFromHandle(world)->CreateBody(
      shape_type, shape_a, shape_b, shape_c, motion_type, x, y, z, friction,
      restitution, is_sensor);
}

JOLT_FFI_EXPORT int64_t jolt_compound_create() {
  return reinterpret_cast<int64_t>(new StaticCompoundShapeSettings());
}

JOLT_FFI_EXPORT void jolt_compound_destroy(int64_t compound) {
  delete CompoundFromHandle(compound);
}

JOLT_FFI_EXPORT void jolt_compound_add_shape(
    int64_t compound, int shape_type, float shape_a, float shape_b,
    float shape_c, float offset_x, float offset_y, float offset_z,
    float rotation_x, float rotation_y, float rotation_z, float rotation_w) {
  CompoundFromHandle(compound)->AddShape(
      Vec3(offset_x, offset_y, offset_z),
      Quat(rotation_x, rotation_y, rotation_z, rotation_w),
      CreateShape(shape_type, shape_a, shape_b, shape_c));
}

JOLT_FFI_EXPORT uint32_t jolt_body_create_compound(
    int64_t world, int64_t compound, int motion_type, float x, float y,
    float z, float friction, float restitution, bool is_sensor) {
  return WorldFromHandle(world)->CreateCompoundBody(
      CompoundFromHandle(compound), motion_type, x, y, z, friction,
      restitution, is_sensor);
}

JOLT_FFI_EXPORT void jolt_body_destroy(int64_t world, uint32_t body) {
  WorldFromHandle(world)->DestroyBody(BodyFromHandle(body));
}

JOLT_FFI_EXPORT float jolt_body_position(int64_t world, uint32_t body,
                                         int component) {
  return WorldFromHandle(world)
      ->physics.GetBodyInterface()
      .GetPosition(BodyFromHandle(body))[component];
}

JOLT_FFI_EXPORT float jolt_body_rotation(int64_t world, uint32_t body,
                                         int component) {
  const Quat rotation = WorldFromHandle(world)
                            ->physics.GetBodyInterface()
                            .GetRotation(BodyFromHandle(body));
  switch (component) {
    case 0:
      return rotation.GetX();
    case 1:
      return rotation.GetY();
    case 2:
      return rotation.GetZ();
    default:
      return rotation.GetW();
  }
}

JOLT_FFI_EXPORT float jolt_body_linear_velocity(int64_t world, uint32_t body,
                                                int component) {
  return WorldFromHandle(world)
      ->physics.GetBodyInterface()
      .GetLinearVelocity(BodyFromHandle(body))[component];
}

JOLT_FFI_EXPORT float jolt_body_angular_velocity(int64_t world, uint32_t body,
                                                 int component) {
  return WorldFromHandle(world)
      ->physics.GetBodyInterface()
      .GetAngularVelocity(BodyFromHandle(body))[component];
}

JOLT_FFI_EXPORT void jolt_body_set_transform(
    int64_t world, uint32_t body, float x, float y, float z, float qx,
    float qy, float qz, float qw, bool activate) {
  WorldFromHandle(world)->physics.GetBodyInterface().SetPositionAndRotation(
      BodyFromHandle(body), RVec3(x, y, z), Quat(qx, qy, qz, qw),
      activate ? EActivation::Activate : EActivation::DontActivate);
}

JOLT_FFI_EXPORT void jolt_body_set_linear_velocity(int64_t world,
                                                    uint32_t body, float x,
                                                    float y, float z) {
  WorldFromHandle(world)->physics.GetBodyInterface().SetLinearVelocity(
      BodyFromHandle(body), Vec3(x, y, z));
}

JOLT_FFI_EXPORT void jolt_body_set_angular_velocity(int64_t world,
                                                     uint32_t body, float x,
                                                     float y, float z) {
  WorldFromHandle(world)->physics.GetBodyInterface().SetAngularVelocity(
      BodyFromHandle(body), Vec3(x, y, z));
}

JOLT_FFI_EXPORT void jolt_body_add_impulse(int64_t world, uint32_t body,
                                           float x, float y, float z) {
  WorldFromHandle(world)->physics.GetBodyInterface().AddImpulse(
      BodyFromHandle(body), Vec3(x, y, z));
}

JOLT_FFI_EXPORT void jolt_body_move_kinematic(
    int64_t world, uint32_t body, float x, float y, float z, float qx,
    float qy, float qz, float qw, float delta_seconds) {
  WorldFromHandle(world)->physics.GetBodyInterface().MoveKinematic(
      BodyFromHandle(body), RVec3(x, y, z), Quat(qx, qy, qz, qw),
      delta_seconds);
}
