#include <mpi.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <string>
#include <system_error>
#include <vector>

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

    const long long total_ll = 1LL * n * n;

    if (total_ll > std::numeric_limits<int>::max())
    {
        return false;
    }

    const int total = static_cast<int>(total_ll);

    data.resize(static_cast<std::size_t>(total));

    for (int i = 0; i < total; ++i)
    {
        if (!(in >> data[static_cast<std::size_t>(i)]))
        {
            return false;
        }
    }

    return true;
}

void print_usage(const std::string& prog, int rank)
{
    if (rank != 0)
    {
        return;
    }

    std::cerr <<
        "Usage:\n"
        "  " << prog << " <side> [baseline_seconds]\n\n"
        "Examples:\n"
        "  srun -n 1 ./build_lab3/lab3_mpi 200\n"
        "  srun -n 4 ./build_lab3/lab3_mpi 200 0.051989\n"
        "  mpirun -np 8 ./build_lab3/lab3_mpi 800 0.433895\n\n"
        "Where:\n"
        "  side              - количество элементов в строке квадратной матрицы\n"
        "  baseline_seconds  - время последовательной версии для расчёта speedup\n";
}

int main(int argc, char* argv[])
{
    MPI_Init(&argc, &argv);

    int rank = 0;
    int size = 0;

    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    int side = 0;
    double baseline_seconds = 0.0;
    int parse_ok = 1;

    if (rank == 0)
    {
        if (argc < 2)
        {
            parse_ok = 0;
        }
        else
        {
            try
            {
                side = std::stoi(argv[1]);

                if (argc > 2)
                {
                    baseline_seconds = std::stod(argv[2]);
                }
            }
            catch (...)
            {
                parse_ok = 0;
            }

            if (side <= 0)
            {
                parse_ok = 0;
            }

            if (baseline_seconds < 0.0)
            {
                baseline_seconds = 0.0;
            }
        }
    }

    MPI_Bcast(&side, 1, MPI_INT, 0, MPI_COMM_WORLD);
    MPI_Bcast(&baseline_seconds, 1, MPI_DOUBLE, 0, MPI_COMM_WORLD);
    MPI_Bcast(&parse_ok, 1, MPI_INT, 0, MPI_COMM_WORLD);

    if (!parse_ok)
    {
        print_usage(argv[0] ? std::string(argv[0]) : std::string("lab3_mpi"), rank);
        MPI_Finalize();
        return 1;
    }

    const long long total_ll = 1LL * side * side;

    if (total_ll > std::numeric_limits<int>::max())
    {
        if (rank == 0)
        {
            std::cerr << "Ошибка: матрица слишком большая для int-индексов MPI\n";
        }

        MPI_Finalize();
        return 1;
    }

    const int total = static_cast<int>(total_ll);

    const std::string matrices_dir = "extra/matrices";
    const std::string res_dir = "extra/res/lab_3";

    const std::string filename_a = "A_" + std::to_string(side) + ".txt";
    const std::string filename_b = "B_" + std::to_string(side) + ".txt";
    const std::string filename_c =
        "C_" + std::to_string(side) + "_p" + std::to_string(size) + ".txt";

    const std::filesystem::path a_path = std::filesystem::path(matrices_dir) / filename_a;
    const std::filesystem::path b_path = std::filesystem::path(matrices_dir) / filename_b;
    const std::filesystem::path c_path = std::filesystem::path(res_dir) / filename_c;

    std::vector<int> A;
    std::vector<int> B;

    int read_ok = 1;

    if (rank == 0)
    {
        int n_a = 0;
        int n_b = 0;

        if (!read_matrix(a_path, n_a, A))
        {
            std::cerr << "Не удалось прочитать матрицу A: " << a_path.string() << "\n";
            std::cerr << "Убедитесь, что файлы матриц лежат в " << matrices_dir << "\n";
            read_ok = 0;
        }
        else if (!read_matrix(b_path, n_b, B))
        {
            std::cerr << "Не удалось прочитать матрицу B: " << b_path.string() << "\n";
            std::cerr << "Убедитесь, что файлы матриц лежат в " << matrices_dir << "\n";
            read_ok = 0;
        }
        else if (n_a != side || n_b != side)
        {
            std::cerr << "Ошибка несоответствия размеров: запрошен " << side
                      << ", прочитано A=" << n_a
                      << ", B=" << n_b << "\n";
            read_ok = 0;
        }
    }

    MPI_Bcast(&read_ok, 1, MPI_INT, 0, MPI_COMM_WORLD);

    if (!read_ok)
    {
        MPI_Finalize();
        return 1;
    }

    B.resize(static_cast<std::size_t>(total));

    const int base_rows = side / size;
    const int rem_rows = side % size;

    std::vector<int> counts(static_cast<std::size_t>(size), 0);
    std::vector<int> displs(static_cast<std::size_t>(size), 0);

    int offset = 0;

    for (int r = 0; r < size; ++r)
    {
        const int rows = base_rows + (r < rem_rows ? 1 : 0);
        counts[static_cast<std::size_t>(r)] = rows * side;
        displs[static_cast<std::size_t>(r)] = offset;
        offset += counts[static_cast<std::size_t>(r)];
    }

    const int local_count = counts[static_cast<std::size_t>(rank)];
    const int local_rows = local_count / side;

    std::vector<int> localA(
        static_cast<std::size_t>(std::max(1, local_count)),
        0
    );

    const int* sendA = (rank == 0 ? A.data() : localA.data());

    MPI_Scatterv(
        sendA,
        counts.data(),
        displs.data(),
        MPI_INT,
        localA.data(),
        local_count,
        MPI_INT,
        0,
        MPI_COMM_WORLD
    );

    MPI_Bcast(
        B.data(),
        total,
        MPI_INT,
        0,
        MPI_COMM_WORLD
    );

    std::vector<int> localC(
        static_cast<std::size_t>(std::max(1, local_count)),
        0
    );

    const double start_time = MPI_Wtime();

    for (int i = 0; i < local_rows; ++i)
    {
        const int* a_row = localA.data() + static_cast<std::size_t>(i) * side;
        int* c_row = localC.data() + static_cast<std::size_t>(i) * side;

        for (int k = 0; k < side; ++k)
        {
            const int aik = a_row[k];

            if (aik == 0)
            {
                continue;
            }

            const int* b_row = B.data() + static_cast<std::size_t>(k) * side;

            for (int j = 0; j < side; ++j)
            {
                c_row[j] += aik * b_row[j];
            }
        }
    }

    const double stop_time = MPI_Wtime();

    double local_time = stop_time - start_time;
    double max_time = 0.0;

    MPI_Allreduce(
        &local_time,
        &max_time,
        1,
        MPI_DOUBLE,
        MPI_MAX,
        MPI_COMM_WORLD
    );

    std::vector<int> C(
        static_cast<std::size_t>(rank == 0 ? total : 1),
        0
    );

    MPI_Gatherv(
        localC.data(),
        local_count,
        MPI_INT,
        C.data(),
        counts.data(),
        displs.data(),
        MPI_INT,
        0,
        MPI_COMM_WORLD
    );

    if (rank == 0)
    {
        std::error_code ec;
        std::filesystem::create_directories(res_dir, ec);

        if (ec)
        {
            std::cerr << "Не удалось создать директорию '" << res_dir << "': "
                      << ec.message() << "\n";
            MPI_Finalize();
            return 1;
        }

        std::ofstream out(c_path);

        if (!out.is_open())
        {
            std::cerr << "Не удалось открыть файл результата: " << c_path.string() << "\n";
            MPI_Finalize();
            return 1;
        }

        const long double un = static_cast<long double>(side);

        const long double operations = 2.0L * un * un * un - un * un;

        const long double memory_bytes =
            3.0L * static_cast<long double>(total) * static_cast<long double>(sizeof(int));

        const long double seconds = static_cast<long double>(max_time);

        const long double gops =
            (seconds > 0.0L)
                ? operations / seconds / 1.0e9L
                : 0.0L;

        const long double speedup =
            (baseline_seconds > 0.0 && seconds > 0.0L)
                ? static_cast<long double>(baseline_seconds) / seconds
                : 0.0L;

        out << std::setprecision(17);

        out << "side=" << side << '\n';
        out << "matrix_size=" << total << '\n';
        out << "processes=" << size << '\n';
        out << "decomposition=rowwise\n";

        out << "time_seconds=" << max_time << '\n';
        out << "time_ms=" << max_time * 1000.0L << '\n';

        out << "integer_operations=" << operations << '\n';
        out << "memory_bytes=" << memory_bytes << '\n';
        out << "gops=" << gops << '\n';

        if (speedup > 0.0L)
        {
            out << "speedup_vs_sequential=" << speedup << '\n';
        }

        out << "a_file=" << a_path.string() << '\n';
        out << "b_file=" << b_path.string() << '\n';
        out << "output_file=" << c_path.string() << '\n';

        out << "--- MATRIX ---\n";

        out << side << '\n';

        for (int i = 0; i < side; ++i)
        {
            const std::size_t row_offset = static_cast<std::size_t>(i) * side;

            for (int j = 0; j < side; ++j)
            {
                out << C[row_offset + static_cast<std::size_t>(j)];

                if (j + 1 < side)
                {
                    out << ' ';
                }
            }

            out << '\n';
        }

        out.flush();

        if (!out.good())
        {
            std::cerr << "Ошибка записи файла результата: " << c_path.string() << "\n";
            MPI_Finalize();
            return 1;
        }

        std::cout << std::setprecision(17);
        std::cout << "side=" << side << "\n";
        std::cout << "matrix_size=" << total << "\n";
        std::cout << "processes=" << size << "\n";
        std::cout << "time_seconds=" << max_time << "\n";
        std::cout << "time_ms=" << max_time * 1000.0L << "\n";
        std::cout << "integer_operations=" << operations << "\n";
        std::cout << "memory_bytes=" << memory_bytes << "\n";
        std::cout << "gops=" << gops << "\n";

        if (speedup > 0.0L)
        {
            std::cout << "speedup_vs_sequential=" << speedup << "\n";
        }

        std::cout << "output_file=" << c_path.string() << "\n";
    }

    MPI_Finalize();
    return 0;
}