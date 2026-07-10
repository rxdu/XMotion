/*
 * bench_imu_attitude
 *
 * Hardware bench: IMU attitude estimation end to end.
 *
 *   xmDriver (HiPNUC IMU) -> Mekf9 (leveling/TRIAD bootstrap) ->
 *   quickviz dashboard + CSV dataset recording
 *
 * The dashboard plots the MEKF estimate AGAINST the device's own fused
 * orientation (two lines per axis) — the bench is a comparison
 * instrument, not just a viewer. Every run can record a CSV dataset
 * (--record) that replays deterministically (--replay), which is the
 * seed format for the golden-log regression tier.
 *
 * Modes (exactly one):
 *   --device /dev/ttyUSB0 [--baud 115200]   live hardware
 *   --replay file.csv                        replay a recording (paced)
 *   --sim                                    synthetic tumbling IMU
 * Options:
 *   --record out.csv                         write the dataset
 *
 * Bootstrap semantics: the first ~0.5 s of samples are averaged with the
 * device assumed STATIONARY; roll/pitch come from leveling and the
 * magnetometer reference is defined from the same window, so yaw is
 * measured RELATIVE TO THE STARTUP HEADING (use MagReferenceEnu + a
 * calibrated magnetometer when absolute heading is needed).
 *
 * Threading follows the quickviz contract: samples/filtering run on the
 * source thread; the GL dashboard only drains latest-only streams.
 *
 * CSV format (one row per sample):
 *   t[s],gx,gy,gz[rad/s],ax,ay,az[m/s^2],mx,my,mz,qw,qx,qy,qz(device)
 *
 * Copyright (c) 2026 Ruixiang Du (rdu)
 */

#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <memory>
#include <random>
#include <map>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "canvas/cairo_widget.hpp"
#include "core/buffer/buffer_registry.hpp"
#include "core/buffer/ring_buffer.hpp"
#include "core/data_stream.hpp"
#include "plot/rt_line_plot_widget.hpp"
#include "viewer/box.hpp"
#include "viewer/viewer.hpp"

#include "sensor_imu/imu_hipnuc.hpp"
#include "xmnav/estimation/attitude_init.hpp"
#include "xmnav/estimation/mekf9.hpp"

using namespace xmotion;

namespace {

constexpr double kGravity = 9.81;
constexpr int kBootstrapSamples = 100;  // ~0.5 s at 200 Hz

struct BenchSample {
  double t = 0.0;  // seconds since start
  Eigen::Vector3d gyro = Eigen::Vector3d::Zero();
  Eigen::Vector3d accel = Eigen::Vector3d::Zero();
  Eigen::Vector3d mag = Eigen::Vector3d::Zero();
  Eigen::Quaterniond device_q = Eigen::Quaterniond::Identity();
};

// latest state for the horizon + status panel
struct DashboardState {
  double roll = 0, pitch = 0, yaw = 0;  // MEKF estimate [rad]
  double bias_norm = 0;
  double sample_rate = 0;
  std::uint64_t samples = 0;
  bool bootstrapping = true;
};

Eigen::Vector3d ToEigen(const Vector3f &v) {
  return {static_cast<double>(v.x), static_cast<double>(v.y),
          static_cast<double>(v.z)};
}

// ZYX Euler from a body-to-world quaternion
Eigen::Vector3d RollPitchYaw(const Eigen::Quaterniond &q) {
  const double w = q.w(), x = q.x(), y = q.y(), z = q.z();
  const double roll = std::atan2(2.0 * (w * x + y * z),
                                 1.0 - 2.0 * (x * x + y * y));
  const double pitch = std::asin(std::clamp(2.0 * (w * y - z * x), -1.0, 1.0));
  const double yaw = std::atan2(2.0 * (w * z + x * y),
                                1.0 - 2.0 * (y * y + z * z));
  return {roll, pitch, yaw};
}

// -------------------------------------------------------------------------
// filter pipeline: bootstrap, MEKF, plot buffers, optional CSV recording
// -------------------------------------------------------------------------
class Pipeline {
 public:
  using PlotPoint = quickviz::RtLinePlotWidget::DataPoint;

  Pipeline(quickviz::DataStream<DashboardState> *dash, std::FILE *record)
      : dash_(dash), record_(record) {
    auto &reg = quickviz::BufferRegistry::GetInstance();
    for (const char *name :
         {"est.roll", "dev.roll", "est.pitch", "dev.pitch", "est.yaw",
          "dev.yaw", "est.bias", "est.accel_norm"}) {
      reg.AddBuffer<PlotPoint>(
          name, std::make_shared<quickviz::RingBuffer<PlotPoint, 2048>>());
      buffers_[name] = *reg.GetBuffer<PlotPoint>(name);
    }
  }

  void OnSample(const BenchSample &s) {
    if (record_ != nullptr) {
      std::fprintf(record_,
                   "%.6f,%.9f,%.9f,%.9f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,"
                   "%.9f,%.9f,%.9f,%.9f\n",
                   s.t, s.gyro.x(), s.gyro.y(), s.gyro.z(), s.accel.x(),
                   s.accel.y(), s.accel.z(), s.mag.x(), s.mag.y(), s.mag.z(),
                   s.device_q.w(), s.device_q.x(), s.device_q.y(),
                   s.device_q.z());
    }
    if (bootstrapping_) {
      Bootstrap(s);
      return;
    }
    const double dt = std::clamp(s.t - last_t_, 1e-4, 0.05);
    last_t_ = s.t;
    if (!mekf_.Update(s.gyro, s.accel, s.mag, dt)) return;
    ++count_;

    const Eigen::Vector3d est = RollPitchYaw(mekf_.GetQuaternion());
    const Eigen::Vector3d dev = RollPitchYaw(s.device_q);
    const float tf = static_cast<float>(s.t);
    constexpr double kDeg = 180.0 / M_PI;
    Push("est.roll", tf, est(0) * kDeg);
    Push("dev.roll", tf, dev(0) * kDeg);
    Push("est.pitch", tf, est(1) * kDeg);
    Push("dev.pitch", tf, dev(1) * kDeg);
    Push("est.yaw", tf, est(2) * kDeg);
    Push("dev.yaw", tf, dev(2) * kDeg);
    Push("est.bias", tf, mekf_.GetGyroBias().norm() * kDeg);
    Push("est.accel_norm", tf, s.accel.norm());

    DashboardState d;
    d.roll = est(0);
    d.pitch = est(1);
    d.yaw = est(2);
    d.bias_norm = mekf_.GetGyroBias().norm();
    d.samples = count_;
    d.sample_rate = dt > 0 ? 1.0 / dt : 0.0;
    d.bootstrapping = false;
    dash_->Push(std::move(d));
  }

 private:
  void Bootstrap(const BenchSample &s) {
    accel_sum_ += s.accel;
    mag_sum_ += s.mag;
    if (++boot_count_ < kBootstrapSamples) return;

    const Eigen::Vector3d accel_mean = accel_sum_ / boot_count_;
    const Eigen::Vector3d mag_mean = mag_sum_ / boot_count_;
    Eigen::Quaterniond q0 = Eigen::Quaterniond::Identity();
    if (!LevelFromAccel(accel_mean, &q0)) {
      std::fprintf(stderr, "bootstrap: degenerate accel mean, using identity\n");
    }
    // field reference from the same window: startup yaw defines zero
    const Eigen::Vector3d mag_ref = q0 * mag_mean;

    Mekf9::Params ep;
    ep.init_quaternion = q0;
    ep.sigma_omega = Eigen::Vector3d::Constant(0.005);
    ep.sigma_f = Eigen::Vector3d::Constant(0.05);
    ep.sigma_beta_omega = Eigen::Vector3d::Constant(2e-4);
    ep.sigma_beta_f = Eigen::Vector3d::Constant(2e-4);
    ep.sigma_beta_m = Eigen::Vector3d::Constant(2e-4);
    ep.init_state_cov = Mekf9::StateCovariance::Identity() * 1e-2;
    ep.init_state_cov.block<3, 3>(0, 0) =
        Eigen::Matrix3d::Identity() * 2.5e-3;  // bootstrapped regime
    ep.accel_noise_cov =
        Mekf9::ObservationNoiseCovariance::Identity() * 0.05 * 0.05;
    ep.mag_noise_cov = Mekf9::ObservationNoiseCovariance::Identity() *
                       std::pow(0.02 * std::max(mag_mean.norm(), 1e-3), 2.0);
    ep.mag_reference = mag_ref;
    ep.mag_gate_threshold = 0.2 * std::max(mag_ref.norm(), 1e-3);
    mekf_.Initialize(ep);
    bootstrapping_ = false;
    last_t_ = s.t;
    std::printf("bootstrap done: roll=%.2f deg pitch=%.2f deg, |m|=%.3f\n",
                RollPitchYaw(q0)(0) * 57.2958, RollPitchYaw(q0)(1) * 57.2958,
                mag_ref.norm());
  }

  void Push(const char *name, float t, double v) {
    buffers_[name]->Write({t, static_cast<float>(v)});
  }

  quickviz::DataStream<DashboardState> *dash_;
  std::FILE *record_;
  std::map<std::string,
           std::shared_ptr<quickviz::BufferInterface<PlotPoint>>>
      buffers_;
  Mekf9 mekf_;
  bool bootstrapping_ = true;
  int boot_count_ = 0;
  Eigen::Vector3d accel_sum_ = Eigen::Vector3d::Zero();
  Eigen::Vector3d mag_sum_ = Eigen::Vector3d::Zero();
  double last_t_ = 0.0;
  std::uint64_t count_ = 0;
};

// -------------------------------------------------------------------------
// sample sources
// -------------------------------------------------------------------------

// synthetic tumbling IMU (the NEES campaign's world, with a mag)
void RunSim(Pipeline *pipeline, std::atomic<bool> *stop) {
  std::mt19937_64 rng(42);
  std::normal_distribution<double> unit;
  auto g3 = [&] { return Eigen::Vector3d(unit(rng), unit(rng), unit(rng)); };
  const Eigen::Vector3d mag_ref(0.35, 0.2, -0.45);
  const Eigen::Vector3d bias_w(0.004, -0.003, 0.002);
  Eigen::Quaterniond q = Eigen::Quaterniond::Identity();
  const double dt = 0.005;
  double t = 0.0;
  while (!stop->load()) {
    Eigen::Vector3d w(0, 0, 0);
    if (t > 1.0) {  // stationary bootstrap window first
      w = Eigen::Vector3d(0.6 * std::sin(0.5 * t), 0.4 * std::sin(0.3 * t + 1),
                          0.5 * std::sin(0.4 * t + 2));
    }
    const Eigen::Vector3d dth = w * dt;
    if (dth.norm() > 1e-15) {
      q = q * Eigen::Quaterniond(Eigen::AngleAxisd(dth.norm(),
                                                   dth.normalized()));
      q.normalize();
    }
    BenchSample s;
    s.t = t;
    s.gyro = w + bias_w + 0.005 / std::sqrt(dt) * g3();
    s.accel = q.conjugate() * Eigen::Vector3d(0, 0, -kGravity) + 0.05 * g3();
    s.mag = q.conjugate() * mag_ref + 0.01 * g3();
    s.device_q = q;  // the "device fusion" reference = truth in sim
    pipeline->OnSample(s);
    t += dt;
    std::this_thread::sleep_for(std::chrono::microseconds(5000));
  }
}

// CSV replay, paced by the recorded timestamps
void RunReplay(Pipeline *pipeline, const std::string &path,
               std::atomic<bool> *stop) {
  std::ifstream in(path);
  if (!in) {
    std::fprintf(stderr, "replay: cannot open %s\n", path.c_str());
    return;
  }
  std::string line;
  double prev_t = -1.0;
  while (!stop->load() && std::getline(in, line)) {
    if (line.empty() || line[0] == '#') continue;
    BenchSample s;
    double qw, qx, qy, qz;
    if (std::sscanf(line.c_str(),
                    "%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf,%lf",
                    &s.t, &s.gyro.x(), &s.gyro.y(), &s.gyro.z(),
                    &s.accel.x(), &s.accel.y(), &s.accel.z(), &s.mag.x(),
                    &s.mag.y(), &s.mag.z(), &qw, &qx, &qy, &qz) != 14) {
      continue;
    }
    s.device_q = Eigen::Quaterniond(qw, qx, qy, qz);
    if (prev_t >= 0.0 && s.t > prev_t) {
      std::this_thread::sleep_for(
          std::chrono::duration<double>(s.t - prev_t));
    }
    prev_t = s.t;
    pipeline->OnSample(s);
  }
  std::printf("replay: end of %s\n", path.c_str());
}

// live hardware via xmDriver
int RunLive(Pipeline *pipeline, const std::string &device,
            std::uint32_t baud, std::atomic<bool> *stop) {
  ImuHipnuc::Config cfg;
  cfg.device = device;
  cfg.baud_rate = baud;
  ImuHipnuc imu(cfg);
  const auto start = std::chrono::steady_clock::now();
  imu.SetSampleCallback([&](const hal::ImuSample &raw) {
    BenchSample s;
    s.t = std::chrono::duration<double>(raw.stamp - start).count();
    s.gyro = ToEigen(raw.gyro);
    s.accel = ToEigen(raw.accel);
    s.mag = ToEigen(raw.mag);
    s.device_q = raw.orientation;
    pipeline->OnSample(s);
  });
  if (imu.Connect() != hal::Status::kOk) {
    std::fprintf(stderr, "live: failed to connect to %s\n", device.c_str());
    return 1;
  }
  std::printf("live: connected to %s @ %u\n", device.c_str(), baud);
  while (!stop->load()) {
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
  }
  imu.Disconnect();
  return 0;
}

// -------------------------------------------------------------------------
// dashboard panels
// -------------------------------------------------------------------------
class StatusPanel : public quickviz::Panel {
 public:
  explicit StatusPanel(const DashboardState *state)
      : Panel("imu_bench_status"), state_(state) {
    SetAutoLayout(true);
    SetNoResize(true);
    SetNoMove(true);
    SetWindowNoMenuButton();
  }
  void Draw() override {
    Begin();
    constexpr double kDeg = 180.0 / M_PI;
    if (state_->bootstrapping) {
      ImGui::Text("BOOTSTRAPPING: keep the IMU stationary...");
    } else {
      ImGui::Text("roll %7.2f deg   pitch %7.2f deg   yaw %7.2f deg",
                  state_->roll * kDeg, state_->pitch * kDeg,
                  state_->yaw * kDeg);
      ImGui::Text("gyro-bias %5.3f deg/s   rate %5.0f Hz   samples %llu",
                  state_->bias_norm * kDeg, state_->sample_rate,
                  static_cast<unsigned long long>(state_->samples));
    }
    End();
  }

 private:
  const DashboardState *state_;
};

// artificial horizon rendered from the MEKF attitude
void DrawHorizon(cairo_t *cr, float aspect, const DashboardState &d) {
  cairo_set_source_rgb(cr, 0.12, 0.12, 0.12);
  cairo_paint(cr);
  const double cx = 0.5 * aspect, cy = 0.5, R = 0.42;
  cairo_save(cr);
  cairo_arc(cr, cx, cy, R, 0, 2 * M_PI);
  cairo_clip(cr);
  cairo_translate(cr, cx, cy);
  cairo_rotate(cr, -d.roll);
  const double pitch_offset = 0.6 * d.pitch;  // rad -> canvas units
  // sky / ground
  cairo_set_source_rgb(cr, 0.22, 0.45, 0.75);
  cairo_rectangle(cr, -1.5, -1.5, 3.0, 1.5 + pitch_offset);
  cairo_fill(cr);
  cairo_set_source_rgb(cr, 0.45, 0.31, 0.17);
  cairo_rectangle(cr, -1.5, pitch_offset, 3.0, 1.5);
  cairo_fill(cr);
  // horizon + pitch ladder (every 10 deg)
  cairo_set_source_rgb(cr, 1, 1, 1);
  cairo_set_line_width(cr, 0.006);
  cairo_move_to(cr, -1.5, pitch_offset);
  cairo_line_to(cr, 1.5, pitch_offset);
  cairo_stroke(cr);
  cairo_set_line_width(cr, 0.003);
  for (int deg = -30; deg <= 30; deg += 10) {
    if (deg == 0) continue;
    const double y = pitch_offset + 0.6 * deg * M_PI / 180.0;
    cairo_move_to(cr, -0.1, y);
    cairo_line_to(cr, 0.1, y);
    cairo_stroke(cr);
  }
  cairo_restore(cr);
  // fixed aircraft symbol + bezel
  cairo_set_source_rgb(cr, 1.0, 0.8, 0.1);
  cairo_set_line_width(cr, 0.008);
  cairo_move_to(cr, cx - 0.15, cy);
  cairo_line_to(cr, cx - 0.04, cy);
  cairo_move_to(cr, cx + 0.04, cy);
  cairo_line_to(cr, cx + 0.15, cy);
  cairo_stroke(cr);
  cairo_arc(cr, cx, cy, 0.012, 0, 2 * M_PI);
  cairo_fill(cr);
  cairo_set_source_rgb(cr, 0.8, 0.8, 0.8);
  cairo_set_line_width(cr, 0.006);
  cairo_arc(cr, cx, cy, R, 0, 2 * M_PI);
  cairo_stroke(cr);
}

quickviz::RtLinePlotWidget *MakeAnglePlot(const char *panel,
                                          const char *est_buf,
                                          const char *dev_buf,
                                          const char *label, float y_range) {
  auto *w = new quickviz::RtLinePlotWidget(panel);
  w->SetAutoLayout(true);
  w->SetAxisLabels("t", label);
  w->SetAxisUnits("s", "deg");
  w->SetFixedHistory(15.0f);
  w->SetYAxisRange(-y_range, y_range);
  w->AddLine("mekf", est_buf);
  w->AddLine("device", dev_buf);
  return w;
}

}  // namespace

int main(int argc, char **argv) {
  std::string device, replay_path, record_path;
  std::uint32_t baud = 115200;
  bool sim = false;
  for (int i = 1; i < argc; ++i) {
    const std::string a = argv[i];
    if (a == "--device" && i + 1 < argc) device = argv[++i];
    else if (a == "--baud" && i + 1 < argc) baud = std::stoul(argv[++i]);
    else if (a == "--replay" && i + 1 < argc) replay_path = argv[++i];
    else if (a == "--record" && i + 1 < argc) record_path = argv[++i];
    else if (a == "--sim") sim = true;
    else {
      std::fprintf(stderr,
                   "usage: bench_imu_attitude (--device PATH [--baud N] | "
                   "--replay FILE | --sim) [--record FILE]\n");
      return 1;
    }
  }
  const int modes = (device.empty() ? 0 : 1) + (replay_path.empty() ? 0 : 1) +
                    (sim ? 1 : 0);
  if (modes != 1) {
    std::fprintf(stderr, "pick exactly one of --device / --replay / --sim\n");
    return 1;
  }

  std::FILE *record = nullptr;
  if (!record_path.empty()) {
    record = std::fopen(record_path.c_str(), "w");
    if (record == nullptr) {
      std::fprintf(stderr, "cannot open %s for writing\n",
                   record_path.c_str());
      return 1;
    }
    std::fprintf(record,
                 "# t[s],gx,gy,gz[rad/s],ax,ay,az[m/s^2],mx,my,mz,"
                 "qw,qx,qy,qz(device)\n");
  }

  quickviz::DataStream<DashboardState> dash_stream;
  Pipeline pipeline(&dash_stream, record);

  std::atomic<bool> stop{false};
  std::thread source;
  int live_result = 0;
  if (sim) {
    source = std::thread(RunSim, &pipeline, &stop);
  } else if (!replay_path.empty()) {
    source = std::thread(RunReplay, &pipeline, replay_path, &stop);
  } else {
    source = std::thread([&] {
      live_result = RunLive(&pipeline, device, baud, &stop);
    });
  }

  // --- dashboard ---
  quickviz::Viewer viewer("xMotion IMU attitude bench", 1500, 900);
  auto dash_state = std::make_shared<DashboardState>();

  auto horizon = std::make_shared<quickviz::CairoWidget>("horizon", true);
  horizon->OnResize(700, 620);
  horizon->SetAutoLayout(true);
  horizon->SetNoResize(true);
  horizon->SetNoMove(true);
  horizon->AttachDrawFunction([&dash_stream, dash_state](cairo_t *cr,
                                                         float aspect) {
    DashboardState d;
    if (dash_stream.TryPull(d)) *dash_state = d;
    DrawHorizon(cr, aspect, *dash_state);
  });

  auto status = std::make_shared<StatusPanel>(dash_state.get());

  std::shared_ptr<quickviz::RtLinePlotWidget> roll_plot(
      MakeAnglePlot("roll_plot", "est.roll", "dev.roll", "roll", 180.0f));
  std::shared_ptr<quickviz::RtLinePlotWidget> pitch_plot(
      MakeAnglePlot("pitch_plot", "est.pitch", "dev.pitch", "pitch", 90.0f));
  std::shared_ptr<quickviz::RtLinePlotWidget> yaw_plot(
      MakeAnglePlot("yaw_plot", "est.yaw", "dev.yaw", "yaw", 180.0f));

  auto left = std::make_shared<quickviz::Box>("left");
  left->SetFlexDirection(quickviz::Styling::FlexDirection::kColumn);
  left->SetAlignItems(quickviz::Styling::AlignItems::kStretch);
  left->SetFlexGrow(1);
  left->SetFlexShrink(1);
  horizon->SetFlexGrow(1);
  horizon->SetFlexShrink(1);
  status->SetHeight(84);
  status->SetFlexGrow(0);
  status->SetFlexShrink(0);
  left->AddChild(horizon);
  left->AddChild(status);

  auto right = std::make_shared<quickviz::Box>("right");
  right->SetFlexDirection(quickviz::Styling::FlexDirection::kColumn);
  right->SetAlignItems(quickviz::Styling::AlignItems::kStretch);
  right->SetFlexGrow(1);
  right->SetFlexShrink(1);
  for (auto &p : {roll_plot, pitch_plot, yaw_plot}) {
    p->SetFlexGrow(1);
    p->SetFlexShrink(1);
    right->AddChild(p);
  }

  auto root = std::make_shared<quickviz::Box>("root");
  root->SetFlexDirection(quickviz::Styling::FlexDirection::kRow);
  root->SetAlignItems(quickviz::Styling::AlignItems::kStretch);
  root->AddChild(left);
  root->AddChild(right);
  viewer.AddSceneObject(root);
  viewer.Show();

  stop.store(true);
  source.join();
  if (record != nullptr) std::fclose(record);
  return live_result;
}
