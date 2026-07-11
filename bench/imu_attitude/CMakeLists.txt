## IMU attitude bench: xmDriver HiPNUC IMU -> Mekf9 (TRIAD/leveling
## bootstrap) -> live quickviz dashboard, with CSV dataset recording and
## deterministic replay/sim modes (runs without hardware).
find_package(Threads REQUIRED)
add_executable(bench_imu_attitude main.cpp)
target_link_libraries(bench_imu_attitude
    sensor_imu       # xmDriver HiPNUC device
    estimation       # xmNavigation MEKF filters + attitude_init
    core viewer plot canvas  # quickviz (components/viewer)
    Threads::Threads)
