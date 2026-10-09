#include <cuda_runtime.h>

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <vector>

#define CUDA_CHECK(call)                                                       \
    do {                                                                       \
        cudaError_t err = call;                                                \
        if (err != cudaSuccess) {                                              \
            std::cerr << "CUDA error at " << __FILE__ << ":" << __LINE__       \
                      << " - " << cudaGetErrorString(err) << "\n";             \
            std::exit(EXIT_FAILURE);                                           \
        }                                                                      \
    } while (0)

bool read_matrix(const std::filesystem::path& path, int& n, std::vector<int>& data)
{
    std::ifstream in(path);
    if (!in.is_open())
    {
        return false;
    }

    if (!(in >> n))
    {
        return false;
    }

    if (n <= 0)
    {
        return false;
    }

    const std::size_t un = static_cast<std::size_t>(n);

    if (un > std::numeric_limits<std::size_t>::max() / un)
    {
        return false;
    }

    const std::size_t total = un * un;
    data.resize(total);

    for (std::size_t i = 0; i < total; ++i)
    {
        if (!(in >> data[i]))
        {
            return false;
        }
    }

    return true;
}

struct Report
{
    int side = 0;
    std::string kernel;
    std::string device_name;

    int tile = 0;
    int block_x = 0;
    int block_y = 0;
    int grid_x = 0;
    int grid_y = 0;

    unsigned long long matrix_size = 0;
    unsigned long long operations = 0;
    unsigned long long memory_bytes = 0;

    double time_seconds = 0.0;

    long double gops = 0.0L;
    long double speedup = 0.0L;

    std::filesystem::path a_path;
    std::filesystem::path b_path;
};

bool write_matrix_with_report(
    const std::filesystem::path& path,
    const std::vector<int>& data,
    const Report& report
)
{
    std::ofstream out(path);
    if (!out.is_open())
    {
        return false;
    }

    out << std::setprecision(17);

    out << "side=" << report.side << '\n';
    out << "matrix_size=" << report.matrix_size << '\n';
    out << "kernel=" << report.kernel << '\n';
    out << "device=" << report.device_name << '\n';

    out << "tile=" << report.tile << '\n';
    out << "block_x=" << report.block_x << '\n';
    out << "block_y=" << report.block_y << '\n';
    out << "grid_x=" << report.grid_x << '\n';
    out << "grid_y=" << report.grid_y << '\n';

    out << "time_seconds=" << report.time_seconds << '\n';
    out << "time_ms=" << report.time_seconds * 1000.0L << '\n';

    out << "integer_operations=" << report.operations << '\n';
    out << "memory_bytes=" << report.memory_bytes << '\n';
    out << "gops=" << report.gops << '\n';

    if (report.speedup > 0.0L)
    {
        out << "speedup_vs_sequential=" << report.speedup << '\n';
    }

    out << "a_file=" << report.a_path.string() << '\n';
    out << "b_file=" << report.b_path.string() << '\n';
    out << "output_file=" << path.string() << '\n';

    out << "--- MATRIX ---\n";

    out << report.side << '\n';

    const std::size_t un = static_cast<std::size_t>(report.side);

    for (std::size_t i = 0; i < un; ++i)
    {
        const std::size_t row_offset = i * un;

        for (std::size_t j = 0; j < un; ++j)
        {
            out << data[row_offset + j];

            if (j + 1 < un)
            {
                out << ' ';
            }
        }

        out << '\n';
    }

    out.flush();
    return out.good();
}

__global__ void multiplyNaive(
    const int* __restrict__ A,
    const int* __restrict__ B,
    int* __restrict__ C,
    int n
)
{
    const int row = blockIdx.y * blockDim.y + threadIdx.y;
    const int col = blockIdx.x * blockDim.x + threadIdx.x;

    if (row < n && col < n)
    {
        long long sum = 0;

        for (int k = 0; k < n; ++k)
        {
            sum += static_cast<long long>(A[row * n + k]) *
                   static_cast<long long>(B[k * n + col]);
        }

        C[row * n + col] = static_cast<int>(sum);
    }
}

__global__ void multiplyTiled(
    const int* __restrict__ A,
    const int* __restrict__ B,
    int* __restrict__ C,
    int n
)
{
    extern __shared__ int smem[];

    const int tile = blockDim.x;

    int* As = smem;
    int* Bs = smem + tile * tile;

    const int tx = threadIdx.x;
    const int ty = threadIdx.y;

    const int row = blockIdx.y * tile + ty;
    const int col = blockIdx.x * tile + tx;

    long long sum = 0;

    const int num_tiles = (n + tile - 1) / tile;

    for (int t = 0; t < num_tiles; ++t)
    {
        const int a_col = t * tile + tx;
        const int b_row = t * tile + ty;

        As[ty * tile + tx] =
            (row < n && a_col < n) ? A[row * n + a_col] : 0;

        Bs[ty * tile + tx] =
            (b_row < n && col < n) ? B[b_row * n + col] : 0;

        __syncthreads();

        for (int k = 0; k < tile; ++k)
        {
            sum += static_cast<long long>(As[ty * tile + k]) *
                   static_cast<long long>(Bs[k * tile + tx]);
        }

        __syncthreads();
    }

    if (row < n && col < n)
    {
        C[row * n + col] = static_cast<int>(sum);
    }
}

void print_usage()
{
    std::cerr <<
        "Usage:\n"
        "  lab4_cuda <side> [tile] [baseline_seconds] [--tiled|--naive]\n\n"
        "Examples:\n"
        "  lab4_cuda 200 16\n"
        "  lab4_cuda 200 32 0.051989 --tiled\n"
        "  lab4_cuda 400 16 0.433895 --naive\n\n"
        "Defaults:\n"
        "  tile = 16\n"
        "  kernel = tiled\n";
}

int main(int argc, char* argv[])
{
    if (argc < 2)
    {
        print_usage();
        return 1;
    }

    int side = 0;
    int tile = 16;
    double baseline_seconds = 0.0;
    bool use_tiled = true;

    std::vector<std::string> positional;

    for (int i = 1; i < argc; ++i)
    {
        const std::string arg = argv[i];

        if (arg == "--tiled")
        {
            use_tiled = true;
        }
        else if (arg == "--naive")
        {
            use_tiled = false;
        }
        else if (arg == "-h" || arg == "--help")
        {
            print_usage();
            return 0;
        }
        else
        {
            positional.push_back(arg);
        }
    }

    if (positional.empty())
    {
        print_usage();
        return 1;
    }

    try
    {
        side = std::stoi(positional[0]);

        if (positional.size() > 1)
        {
            tile = std::stoi(positional[1]);
        }

        if (positional.size() > 2)
        {
            baseline_seconds = std::stod(positional[2]);
        }
    }
    catch (...)
    {
        std::cerr << "Ошибка: неверный формат аргументов\n";
        print_usage();
        return 1;
    }

    if (side <= 0)
    {
        std::cerr << "Ошибка: side должен быть больше нуля\n";
        return 1;
    }

    if (tile < 1 || tile > 32)
    {
        std::cerr << "Ошибка: tile должен быть в диапазоне 1..32\n";
        std::cerr << "Для квадратного блока tile x tile максимум обычно 32x32 = 1024 темы\n";
        return 1;
    }

    cudaDeviceProp prop;
    CUDA_CHECK(cudaGetDeviceProperties(&prop, 0));

    const int max_square_tile =
        static_cast<int>(std::sqrt(static_cast<double>(prop.maxThreadsPerBlock)));

    if (tile > max_square_tile)
    {
        std::cerr << "Ошибка: tile=" << tile
                  << " слишком большой для этого GPU.\n"
                  << "Максимальный квадратный tile примерно: "
                  << max_square_tile << "\n";
        return 1;
    }

    const std::size_t shared_bytes =
        2ULL * static_cast<std::size_t>(tile) * static_cast<std::size_t>(tile) * sizeof(int);

    if (use_tiled && shared_bytes > prop.sharedMemPerBlock)
    {
        std::cerr << "Ошибка: для tiled kernel нужно "
                  << shared_bytes << " байт shared memory, а доступно "
                  << prop.sharedMemPerBlock << " байт\n";
        return 1;
    }

    const std::string matrices_dir = "extra/matrices";
    const std::string res_dir = "extra/res/lab_4";

    const std::string kernel_name = use_tiled ? "tiled" : "naive";

    const std::string filename_a = "A_" + std::to_string(side) + ".txt";
    const std::string filename_b = "B_" + std::to_string(side) + ".txt";
    const std::string filename_c =
        "C_" + std::to_string(side) + "_" + kernel_name + "_t" + std::to_string(tile) + ".txt";

    const std::filesystem::path a_path = std::filesystem::path(matrices_dir) / filename_a;
    const std::filesystem::path b_path = std::filesystem::path(matrices_dir) / filename_b;
    const std::filesystem::path c_path = std::filesystem::path(res_dir) / filename_c;

    std::error_code ec;
    std::filesystem::create_directories(res_dir, ec);

    if (ec)
    {
        std::cerr << "Не удалось создать директорию '" << res_dir << "': "
                  << ec.message() << "\n";
        return 1;
    }

    int n_a_read = 0;
    int n_b_read = 0;

    std::vector<int> A;
    std::vector<int> B;
    std::vector<int> C;

    std::cout << "GPU: " << prop.name << "\n";
    std::cout << "Max threads per block: " << prop.maxThreadsPerBlock << "\n";
    std::cout << "Shared memory per block: " << prop.sharedMemPerBlock << " bytes\n";

    std::cout << "Чтение матрицы A из " << a_path.string() << "\n";

    if (!read_matrix(a_path, n_a_read, A))
    {
        std::cerr << "Не удалось прочитать матрицу A: " << a_path.string() << "\n";
        std::cerr << "Сначала запусти генератор, например:\n";
        std::cerr << "./build/extra/MatrixGenerator " << side << "\n";
        return 1;
    }

    std::cout << "Чтение матрицы B из " << b_path.string() << "\n";

    if (!read_matrix(b_path, n_b_read, B))
    {
        std::cerr << "Не удалось прочитать матрицу B: " << b_path.string() << "\n";
        std::cerr << "Сначала запусти генератор, например:\n";
        std::cerr << "./build/extra/MatrixGenerator " << side << "\n";
        return 1;
    }

    if (n_a_read != side || n_b_read != side)
    {
        std::cerr << "Ошибка несоответствия размеров: запрошен " << side
                  << ", прочитано A=" << n_a_read
                  << ", B=" << n_b_read << "\n";
        return 1;
    }

    std::cout << "Матрицы загружены успешно. Размер "
              << side << "x" << side << "\n";

    std::cout << "Kernel: " << kernel_name << "\n";
    std::cout << "Block: " << tile << "x" << tile << "\n";

    const std::size_t elements = static_cast<std::size_t>(side) * static_cast<std::size_t>(side);
    const std::size_t bytes = elements * sizeof(int);

    int* d_A = nullptr;
    int* d_B = nullptr;
    int* d_C = nullptr;

    CUDA_CHECK(cudaMalloc(reinterpret_cast<void**>(&d_A), bytes));
    CUDA_CHECK(cudaMalloc(reinterpret_cast<void**>(&d_B), bytes));
    CUDA_CHECK(cudaMalloc(reinterpret_cast<void**>(&d_C), bytes));

    CUDA_CHECK(cudaMemcpy(d_A, A.data(), bytes, cudaMemcpyHostToDevice));
    CUDA_CHECK(cudaMemcpy(d_B, B.data(), bytes, cudaMemcpyHostToDevice));

    const int grid_x = (side + tile - 1) / tile;
    const int grid_y = (side + tile - 1) / tile;

    dim3 block(tile, tile, 1);
    dim3 grid(grid_x, grid_y, 1);

    std::cout << "Grid: " << grid_x << "x" << grid_y << "\n";
    std::cout << "Начало CUDA-умножения...\n";

    cudaEvent_t start_event;
    cudaEvent_t stop_event;

    CUDA_CHECK(cudaEventCreate(&start_event));
    CUDA_CHECK(cudaEventCreate(&stop_event));

    CUDA_CHECK(cudaEventRecord(start_event));

    if (use_tiled)
    {
        multiplyTiled<<<grid, block, shared_bytes>>>(d_A, d_B, d_C, side);
    }
    else
    {
        multiplyNaive<<<grid, block>>>(d_A, d_B, d_C, side);
    }

    CUDA_CHECK(cudaGetLastError());
    CUDA_CHECK(cudaEventRecord(stop_event));
    CUDA_CHECK(cudaEventSynchronize(stop_event));

    float milliseconds = 0.0F;
    CUDA_CHECK(cudaEventElapsedTime(&milliseconds, start_event, stop_event));

    const double seconds = static_cast<double>(milliseconds) / 1000.0;

    std::cout << "CUDA kernel выполнен за " << seconds << " секунд\n";

    C.resize(elements);
    CUDA_CHECK(cudaMemcpy(C.data(), d_C, bytes, cudaMemcpyDeviceToHost));

    CUDA_CHECK(cudaEventDestroy(start_event));
    CUDA_CHECK(cudaEventDestroy(stop_event));

    CUDA_CHECK(cudaFree(d_A));
    CUDA_CHECK(cudaFree(d_B));
    CUDA_CHECK(cudaFree(d_C));

    const unsigned long long un = static_cast<unsigned long long>(side);

    Report report;
    report.side = side;
    report.kernel = kernel_name;
    report.device_name = prop.name;

    report.tile = tile;
    report.block_x = tile;
    report.block_y = tile;
    report.grid_x = grid_x;
    report.grid_y = grid_y;

    report.matrix_size = un * un;

    // 2*N^3 - N^2
    report.operations = 2ULL * un * un * un - un * un;

    // A + B + C
    report.memory_bytes = 3ULL * un * un * static_cast<unsigned long long>(sizeof(int));

    report.time_seconds = seconds;
    report.a_path = a_path;
    report.b_path = b_path;

    const long double seconds_ld = static_cast<long double>(seconds);

    if (seconds > 0.0)
    {
        report.gops =
            static_cast<long double>(report.operations) / seconds_ld / 1.0e9L;
    }

    if (baseline_seconds > 0.0 && seconds > 0.0)
    {
        const long double baseline_ld = static_cast<long double>(baseline_seconds);
        report.speedup = baseline_ld / seconds_ld;
    }

    std::cout << "Запись результата и отчёта в " << c_path.string() << "\n";

    if (!write_matrix_with_report(c_path, C, report))
    {
        std::cerr << "Не удалось записать результат: " << c_path.string() << "\n";
        return 1;
    }

    std::cout << std::setprecision(17);
    std::cout << "side=" << report.side << "\n";
    std::cout << "matrix_size=" << report.matrix_size << "\n";
    std::cout << "kernel=" << report.kernel << "\n";
    std::cout << "device=" << report.device_name << "\n";
    std::cout << "tile=" << report.tile << "\n";
    std::cout << "block_x=" << report.block_x << "\n";
    std::cout << "block_y=" << report.block_y << "\n";
    std::cout << "grid_x=" << report.grid_x << "\n";
    std::cout << "grid_y=" << report.grid_y << "\n";
    std::cout << "time_seconds=" << report.time_seconds << "\n";
    std::cout << "time_ms=" << report.time_seconds * 1000.0L << "\n";
    std::cout << "integer_operations=" << report.operations << "\n";
    std::cout << "memory_bytes=" << report.memory_bytes << "\n";
    std::cout << "gops=" << report.gops << "\n";

    if (report.speedup > 0.0L)
    {
        std::cout << "speedup_vs_sequential=" << report.speedup << "\n";
    }

    std::cout << "output_file=" << c_path.string() << "\n";

    return 0;
}