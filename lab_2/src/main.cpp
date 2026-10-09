#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <vector>
#include <omp.h>

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
    int threads = 0;

    unsigned long long matrix_size = 0;
    unsigned long long operations = 0;
    unsigned long long memory_bytes = 0;

    double time_seconds = 0.0;

    long double gops = 0.0L;
    long double speedup = 0.0L;
    long double efficiency = 0.0L;

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
    out << "threads=" << report.threads << '\n';

    out << "time_seconds=" << report.time_seconds << '\n';
    out << "time_ms=" << report.time_seconds * 1000.0L << '\n';

    out << "integer_operations=" << report.operations << '\n';
    out << "memory_bytes=" << report.memory_bytes << '\n';
    out << "gops=" << report.gops << '\n';

    if (report.speedup > 0.0L)
    {
        out << "speedup_vs_sequential=" << report.speedup << '\n';
    }

    if (report.efficiency > 0.0L)
    {
        out << "efficiency=" << report.efficiency << '\n';
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

void multiply_matrices_omp(
    const std::vector<int>& a,
    const std::vector<int>& b,
    std::vector<int>& c,
    int n
)
{
    const std::size_t un = static_cast<std::size_t>(n);
    const std::size_t total = un * un;

    c.assign(total, 0);

    #pragma omp parallel for schedule(static)
    for (int i = 0; i < n; ++i)
    {
        const std::size_t a_row_start = static_cast<std::size_t>(i) * un;
        const std::size_t c_row_start = static_cast<std::size_t>(i) * un;

        for (int k = 0; k < n; ++k)
        {
            const int aik = a[a_row_start + static_cast<std::size_t>(k)];

            if (aik == 0)
            {
                continue;
            }

            const std::size_t b_row_start = static_cast<std::size_t>(k) * un;

            for (int j = 0; j < n; ++j)
            {
                c[c_row_start + static_cast<std::size_t>(j)] +=
                    aik * b[b_row_start + static_cast<std::size_t>(j)];
            }
        }
    }
}

int main(int argc, char* argv[])
{
    int side = 0;
    int requested_threads = 0;
    double baseline_seconds = 0.0;

    if (argc > 1)
    {
        try
        {
            side = std::stoi(argv[1]);
        }
        catch (...)
        {
            std::cerr << "Ошибка: неверный формат размера '" << argv[1] << "'\n";
            return 1;
        }
    }
    else
    {
        std::cerr << "Использование: lab2 <side> [threads] [baseline_seconds]\n";
        std::cerr << "Пример: lab2 200 4\n";
        std::cerr << "Пример с baseline: lab2 200 4 0.051989\n";
        return 1;
    }

    if (argc > 2)
    {
        try
        {
            requested_threads = std::stoi(argv[2]);
        }
        catch (...)
        {
            std::cerr << "Ошибка: неверный формат количества потоков '" << argv[2] << "'\n";
            return 1;
        }
    }
    else
    {
        requested_threads = omp_get_max_threads();
    }

    if (argc > 3)
    {
        try
        {
            baseline_seconds = std::stod(argv[3]);
        }
        catch (...)
        {
            std::cerr << "Ошибка: неверный формат baseline времени '" << argv[3] << "'\n";
            return 1;
        }
    }

    if (side <= 0)
    {
        std::cerr << "Ошибка: размер должен быть больше нуля\n";
        return 1;
    }

    if (requested_threads <= 0)
    {
        std::cerr << "Ошибка: количество потоков должно быть больше нуля\n";
        return 1;
    }

    omp_set_num_threads(requested_threads);

    int actual_threads = 1;

    #pragma omp parallel
    {
        #pragma omp single
        actual_threads = omp_get_num_threads();
    }

    const std::string matrices_dir = "extra/matrices";
    const std::string res_dir = "extra/res/lab_2";

    const std::string filename_a = "A_" + std::to_string(side) + ".txt";
    const std::string filename_b = "B_" + std::to_string(side) + ".txt";
    const std::string filename_c =
        "C_" + std::to_string(side) + "_t" + std::to_string(requested_threads) + ".txt";

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

    std::cout << "Запрошено потоков: " << requested_threads << "\n";
    std::cout << "Реально потоков: " << actual_threads << "\n";

    std::cout << "Начало параллельного умножения...\n";

    const auto start = std::chrono::steady_clock::now();

    multiply_matrices_omp(A, B, C, side);

    const auto finish = std::chrono::steady_clock::now();

    const std::chrono::duration<double> elapsed = finish - start;
    const double seconds = elapsed.count();

    std::cout << "Умножение завершено за " << seconds << " секунд\n";

    const unsigned long long uside = static_cast<unsigned long long>(side);

    Report report;
    report.side = side;
    report.threads = actual_threads;
    report.matrix_size = uside * uside;

    report.operations = 2ULL * uside * uside * uside - uside * uside;

    report.memory_bytes =
        3ULL * report.matrix_size * static_cast<unsigned long long>(sizeof(int));

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
        report.efficiency =
            report.speedup / static_cast<long double>(actual_threads);
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
    std::cout << "threads=" << report.threads << "\n";
    std::cout << "time_seconds=" << report.time_seconds << "\n";
    std::cout << "time_ms=" << report.time_seconds * 1000.0L << "\n";
    std::cout << "integer_operations=" << report.operations << "\n";
    std::cout << "memory_bytes=" << report.memory_bytes << "\n";
    std::cout << "gops=" << report.gops << "\n";

    if (report.speedup > 0.0L)
    {
        std::cout << "speedup_vs_sequential=" << report.speedup << "\n";
    }

    if (report.efficiency > 0.0L)
    {
        std::cout << "efficiency=" << report.efficiency << "\n";
    }

    std::cout << "output_file=" << c_path.string() << "\n";

    return 0;
}