import std;

int main(int argc, char* argv[])
{
    int n = 0;
    unsigned long long seed = std::random_device{}();
    std::string dir = "extra/matrices";

    if (argc > 1)
    {
        try {
            n = std::stoi(argv[1]);
        } catch (...) {
            std::println("Ошибка: неверный формат размера '{}'", argv[1]);
            return 1;
        }
    }
    else
    {
        std::println("Введите размер квадратной матрицы:");
        std::cin >> n;
    }

    if (argc > 2)
    {
        try {
            seed = std::stoull(argv[2]);
        } catch (...) {
             std::println("Ошибка: неверный формат seed '{}'", argv[2]);
             return 1;
        }
    }

    if (argc > 3)
    {
        dir = argv[3];
    }

    if (n <= 0)
    {
        std::cerr << "Ошибка: размер должен быть больше нуля\n";
        return 1;
    }

    const std::filesystem::path out_dir = dir;

    std::error_code ec;
    std::filesystem::create_directories(out_dir, ec);
    if (ec) {
        std::cerr << "Не удалось создать директорию '" << out_dir.string() << "': " << ec.message() << "\n";
        return 1;
    }

    std::mt19937_64 rng(seed);
    std::uniform_int_distribution<int> dist(-100, 100);

    const std::string filename_a = "A_" + std::to_string(n) + ".txt";
    const std::string filename_b = "B_" + std::to_string(n) + ".txt";

    auto write_matrix = [&](const std::string& filename) -> bool
    {
        const std::filesystem::path file_path = out_dir / filename;
        std::ofstream file(file_path);

        if (!file.is_open())
        {
            std::cerr << "Не удалось открыть файл для записи: " << file_path.string() << "\n";
            return false;
        }

        file << n << '\n';

        for (int i = 0; i < n; ++i)
        {
            for (int j = 0; j < n; ++j)
            {
                file << dist(rng);

                if (j + 1 < n)
                {
                    file << ' ';
                }
            }
            file << '\n';
        }
        
        std::println("Записана матрица в {}", file_path.string());
        return true;
    };

    if (!write_matrix(filename_a)) return 1;
    if (!write_matrix(filename_b)) return 1;

    std::println("\nУспешно созданы две матрицы {}x{}", n, n);
    std::println("Seed использован: {}", seed);
    std::println("Файлы сохранены в директорию: {}", out_dir.string());

    return 0;
}