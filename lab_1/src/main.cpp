import std;

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
    int n = 0;
    double time_seconds = 0.0;

    long double operations = 0.0L;
    long double memory_bytes = 0.0L;
    long double gops = 0.0L;

    std::filesystem::path a_path;
    std::filesystem::path b_path;
};

bool write_matrix_with_report(
    const std::filesystem::path& path,
    int n,
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

    out << "N=" << report.n << '\n';
    out << "time_seconds=" << report.time_seconds << '\n';
    out << "time_ms=" << report.time_seconds * 1000.0L << '\n';
    out << "integer_operations=" << report.operations << '\n';
    out << "memory_bytes=" << report.memory_bytes << '\n';
    out << "gops=" << report.gops << '\n';
    out << "a_file=" << report.a_path.string() << '\n';
    out << "b_file=" << report.b_path.string() << '\n';
    out << "output_file=" << path.string() << '\n';

    out << "--- MATRIX ---\n";

    out << n << '\n';

    const std::size_t un = static_cast<std::size_t>(n);

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

void multiply_matrices(
    const std::vector<int>& a,
    const std::vector<int>& b,
    std::vector<int>& c,
    int n
)
{
    const std::size_t un = static_cast<std::size_t>(n);
    const std::size_t total = un * un;

    c.assign(total, 0);

    for (std::size_t i = 0; i < un; ++i)
    {
        const std::size_t a_row_start = i * un;
        const std::size_t c_row_start = i * un;

        for (std::size_t k = 0; k < un; ++k)
        {
            const int aik = a[a_row_start + k];

            if (aik == 0)
            {
                continue;
            }

            const std::size_t b_row_start = k * un;

            for (std::size_t j = 0; j < un; ++j)
            {
                c[c_row_start + j] += aik * b[b_row_start + j];
            }
        }
    }
}

int main(int argc, char* argv[])
{
    int n = 0;

    if (argc > 1)
    {
        try
        {
            n = std::stoi(argv[1]);
        }
        catch (...)
        {
            std::cerr << "Ошибка: неверный формат размера '" << argv[1] << "'\n";
            return 1;
        }
    }
    else
    {
        std::println("Доступные размеры: 20, 100, 250, 500, 1000, 1500, 2000");
        std::println("Введите размер квадратной матрицы N:");

        if (!(std::cin >> n))
        {
            std::cerr << "Ошибка ввода\n";
            return 1;
        }
    }

    if (n <= 0)
    {
        std::cerr << "Ошибка: размер должен быть больше нуля\n";
        return 1;
    }

    const std::string matrices_dir = "extra/matrices";
    const std::string res_dir = "extra/res";

    const std::string filename_a = "A_" + std::to_string(n) + ".txt";
    const std::string filename_b = "B_" + std::to_string(n) + ".txt";
    const std::string filename_c = "C_" + std::to_string(n) + ".txt";

    const std::filesystem::path a_path = std::filesystem::path(matrices_dir) / filename_a;
    const std::filesystem::path b_path = std::filesystem::path(matrices_dir) / filename_b;
    const std::filesystem::path c_path = std::filesystem::path(res_dir) / filename_c;

    std::error_code ec;
    std::filesystem::create_directories(res_dir, ec);

    if (ec)
    {
        std::cerr << "Не удалось создать директорию '" << res_dir << "': " << ec.message() << "\n";
        return 1;
    }

    int n_a_read = 0;
    int n_b_read = 0;

    std::vector<int> A;
    std::vector<int> B;
    std::vector<int> C;

    std::println("Чтение матрицы A из {}", a_path.string());

    if (!read_matrix(a_path, n_a_read, A))
    {
        std::cerr << "Не удалось прочитать матрицу A: " << a_path.string() << "\n";
        std::cerr << "Сначала запусти генератор, например:\n";
        std::cerr << "./build/extra/MatrixGenerator " << n << "\n";
        return 1;
    }

    std::println("Чтение матрицы B из {}", b_path.string());

    if (!read_matrix(b_path, n_b_read, B))
    {
        std::cerr << "Не удалось прочитать матрицу B: " << b_path.string() << "\n";
        std::cerr << "Сначала запусти генератор, например:\n";
        std::cerr << "./build/extra/MatrixGenerator " << n << "\n";
        return 1;
    }

    if (n_a_read != n || n_b_read != n)
    {
        std::cerr << "Ошибка несоответствия размеров: запрошен " << n
                  << ", прочитано A=" << n_a_read
                  << ", B=" << n_b_read << "\n";
        return 1;
    }

    std::println("Матрицы загружены успешно. Размер {}x{}", n, n);

    std::println("Начало умножения...");

    const auto start = std::chrono::steady_clock::now();

    multiply_matrices(A, B, C, n);

    const auto finish = std::chrono::steady_clock::now();

    const std::chrono::duration<double> elapsed = finish - start;
    const double seconds = elapsed.count();

    std::println("Умножение завершено за {:.6f} секунд", seconds);

    const long double un_ld = static_cast<long double>(n);

    const long double operations = 2.0L * un_ld * un_ld * un_ld - un_ld * un_ld;

    const long double memory_bytes =
        3.0L * un_ld * un_ld * static_cast<long double>(sizeof(int));

    const long double gops =
        (seconds > 0.0)
            ? operations / static_cast<long double>(seconds) / 1.0e9L
            : 0.0L;

    Report report;
    report.n = n*n;
    report.time_seconds = seconds;
    report.operations = operations;
    report.memory_bytes = memory_bytes;
    report.gops = gops;
    report.a_path = a_path;
    report.b_path = b_path;

    std::println("Запись результата и отчёта в {}", c_path.string());

    if (!write_matrix_with_report(c_path, n, C, report))
    {
        std::cerr << "Не удалось записать результат: " << c_path.string() << "\n";
        return 1;
    }

    std::println("matrix_size={}", n*n);
    std::println("time_seconds={:.6f}", seconds);
    std::println("time_ms={:.6f}", seconds * 1000.0);
    std::println("integer_operations={}", static_cast<double>(operations));
    std::println("memory_bytes={}", static_cast<double>(memory_bytes));
    std::println("gops={:.6f}", static_cast<double>(gops));
    std::println("output_file={}", c_path.string());

    return 0;
}
