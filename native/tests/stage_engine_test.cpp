#include "stage_3d/stage_engine.h"

#include <cassert>
#include <cmath>

namespace {

bool Near(float first, float second) {
  return std::abs(first - second) < 0.0001f;
}

}  // namespace

int main() {
  assert(stage_engine_abi_version() == 5);

  StageEngine* engine = stage_engine_create();
  assert(engine != nullptr);

  stage_engine_set_viewport(engine, StageViewport{0, 720, 0.0f});
  const StageViewport viewport = stage_engine_get_viewport(engine);
  assert(viewport.width == 1);
  assert(viewport.height == 720);
  assert(viewport.pixel_ratio == 0.1f);

  StageCamera camera = stage_engine_get_camera(engine);
  camera.vertical_fov_degrees = 300.0f;
  camera.near_plane = -1.0f;
  camera.far_plane = -2.0f;
  stage_engine_set_camera(engine, camera);

  camera = stage_engine_get_camera(engine);
  assert(camera.vertical_fov_degrees == 179.0f);
  assert(camera.near_plane == 0.001f);
  assert(camera.far_plane == 0.002f);

  stage_engine_set_orbit_camera(
      engine,
      StageOrbitCamera{1.0f, 2.0f, 3.0f, 0.0f, 9.0f, 0.0f});
  StageOrbitCamera orbit = stage_engine_get_orbit_camera(engine);
  assert(orbit.pitch == 1.45f);
  assert(orbit.distance == 0.1f);

  stage_engine_reset_camera(engine);
  stage_engine_move_camera(engine, 250.0f, 0.0f);
  orbit = stage_engine_get_orbit_camera(engine);
  assert(orbit.target_x == 1.0f);

  StageEnvironment environment =
      StageEnvironment{0.1f, 0.2f, 0.3f, 2.0f, -1.0f, 4.0f};
  stage_engine_set_environment(engine, environment);
  environment = stage_engine_get_environment(engine);
  assert(environment.sky_a == 1.0f);
  assert(environment.ambient_intensity == 0.0f);
  assert(environment.reflection_intensity == 1.0f);

  StageLight light{
      7,
      STAGE_LIGHT_POINT,
      1.0f,
      0.5f,
      0.25f,
      -10.0f,
      1.0f,
      2.0f,
      3.0f,
      0.0f,
      -1.0f,
      0.0f,
      0.0f,
      1,
  };
  stage_engine_upsert_light(engine, light);
  assert(stage_engine_light_count(engine) == 1);
  assert(stage_engine_get_light(engine, 7, &light) == 1);
  assert(light.intensity == 0.0f);
  assert(light.falloff_radius == 0.001f);
  stage_engine_set_light_intensity(engine, 7, 500.0f);
  assert(stage_engine_get_light(engine, 7, &light) == 1);
  assert(light.intensity == 500.0f);
  stage_engine_remove_light(engine, 7);
  assert(stage_engine_light_count(engine) == 0);

  stage_engine_register_model_asset(
      engine,
      3,
      1.0f,
      STAGE_MODEL_ANCHOR_CENTER,
      StageModelBounds{1.0f, 2.0f, 3.0f, 1.0f, 2.0f, 4.0f});
  assert(stage_engine_has_model_asset(engine, 3) == 1);
  assert(stage_engine_model_asset_count(engine) == 1);
  assert(stage_engine_create_model_instance(engine, 9, 3) == 1);
  stage_engine_set_model_transform(
      engine,
      9,
      StageModelTransform{
          10.0f, 20.0f, 30.0f,
          0.0f, 0.0f, 0.0f, 1.0f,
      });
  float matrix[16]{};
  assert(stage_engine_get_model_matrix(engine, 9, matrix) == 1);
  assert(Near(matrix[0], 0.25f));
  assert(Near(matrix[5], 0.25f));
  assert(Near(matrix[10], 0.25f));
  assert(Near(matrix[12], 0.95f));
  assert(Near(matrix[13], 1.672f));
  assert(Near(matrix[14], -8.35f));

  stage_engine_play_model_animation(
      engine, 9, 2, 1, 2.0f, 1000000000LL, 0);
  int32_t animation_index = -1;
  float animation_time = -1.0f;
  assert(stage_engine_sample_model_animation(
             engine,
             9,
             2500000000LL,
             2.0f,
             &animation_index,
             &animation_time) == 1);
  assert(animation_index == 2);
  assert(Near(animation_time, 1.0f));
  stage_engine_pause_model_animation(engine, 9, 3000000000LL);
  assert(stage_engine_sample_model_animation(
             engine,
             9,
             9000000000LL,
             10.0f,
             &animation_index,
             &animation_time) == 1);
  assert(Near(animation_time, 4.0f));
  stage_engine_resume_model_animation(engine, 9, 5000000000LL);
  assert(stage_engine_sample_model_animation(
             engine,
             9,
             6000000000LL,
             10.0f,
             &animation_index,
             &animation_time) == 1);
  assert(Near(animation_time, 6.0f));
  stage_engine_stop_model_animation(engine, 9);
  assert(stage_engine_sample_model_animation(
             engine,
             9,
             6000000000LL,
             10.0f,
             &animation_index,
             &animation_time) == 0);

  assert(stage_engine_remove_model_asset(engine, 3) == 0);
  stage_engine_remove_model_instance(engine, 9);
  assert(stage_engine_model_instance_count(engine) == 0);
  assert(stage_engine_remove_model_asset(engine, 3) == 1);
  assert(stage_engine_model_asset_count(engine) == 0);

  stage_engine_destroy(engine);
  stage_engine_destroy(nullptr);
  return 0;
}
