#include <cerrno>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <iostream>
#include <random>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>

static std::string join_path(const std::string& a, const std::string& b)
{
    if (a.empty())
    {
        return b;
    }

    if (a[a.size() - 1] == '/')
    {
        return a + b;
    }

    return a + "/" + b;
}

static bool ensure_directory(const std::string& path)
{
    if (path.empty())
    {
        return true;
    }

    std::string cur;
    std::size_t start = 0;

    if (path[0] == '/')
    {
        cur = "/";
        start = 1;
    }

    while (true)
    {
        std::size_t pos = path.find('/', start);

        std::string part;

        if (pos == std::string::npos)
        {
            part = path.substr(start);
        }
        else
        {
            part = path.substr(start, pos - start);
        }

        if (!part.empty())
        {
            cur += part;

            if (mkdir(cur.c_str(), 0775) != 0 && errno != EEXIST)
            {
                return false;
            }

            if (pos != std::string::npos)
            {
                cur += '/';
            }
        }

        if (pos == std::string::npos)
        {
            break;
        }

        start = pos + 1;
    }

    return true;
}

static bool write_matrix(
    const std::string& path,
    int side,
    std::mt19937_64& rng,
    std::uniform_int_distribution<int>& dist
)
{
    std::ofstream out(path.c_str());

    if (!out.is_open())
    {
        std::cerr << "Не удалось открыть файл для записи: " << path << "\n";
        return false;
    }

    out << side << '\n';

    for (int i = 0; i < side; ++i)
    {
        for (int j = 0; j < side; ++j)
        {
            out << dist(rng);

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
        std::cerr << "Ошибка записи файла: " << path << "\n";
        return false;
    }

    std::cout << "Записана матрица: " << path << "\n";
    return true;
}

int main(int argc, char* argv[])
{
    if (argc < 2)
    {
        std::cerr << "Usage: gen_matrices <side> [seed] [dir]\n";
        std::cerr << "Example: gen_matrices 200 12345 extra/matrices\n";
        return 1;
    }

    int side = std::atoi(argv[1]);

    if (side <= 0)
    {
        std::cerr << "Ошибка: размер должен быть больше нуля\n";
        return 1;
    }

    unsigned long long seed = static_cast<unsigned long long>(std::time(NULL));

    if (argc > 2)
    {
        seed = std::strtoull(argv[2], NULL, 10);
    }

    std::string dir = "extra/matrices";

    if (argc > 3)
    {
        dir = argv[3];
    }

    if (!ensure_directory(dir))
    {
        std::cerr << "Не удалось создать директорию: " << dir << "\n";
        return 1;
    }

    std::mt19937_64 rng(seed);
    std::uniform_int_distribution<int> dist(-100, 100);

    const std::string filename_a = "A_" + std::to_string(side) + ".txt";
    const std::string filename_b = "B_" + std::to_string(side) + ".txt";

    const std::string path_a = join_path(dir, filename_a);
    const std::string path_b = join_path(dir, filename_b);

    if (!write_matrix(path_a, side, rng, dist))
    {
        return 1;
    }

    if (!write_matrix(path_b, side, rng, dist))
    {
        return 1;
    }

    std::cout << "Готово. Seed: " << seed << "\n";

    return 0;
}