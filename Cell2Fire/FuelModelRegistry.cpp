#include "FuelModelRegistry.h"

#include <fstream>
#include <iostream>
#include <sstream>
#include <vector>

namespace
{
std::string trim(const std::string& s)
{
    const auto first = s.find_first_not_of(" \t\r\n");
    if (first == std::string::npos)
        return "";
    const auto last = s.find_last_not_of(" \t\r\n");
    return s.substr(first, last - first + 1);
}

float parseFloat(const std::string& token)
{
    if (token.empty())
        return 0.0f;
    return std::stof(token);
}
}

FuelModelRegistry&
FuelModelRegistry::instance()
{
    static FuelModelRegistry registry;
    return registry;
}

bool
FuelModelRegistry::ensureLoaded(const std::string& csv_path)
{
    if (loaded_ && source_ == csv_path)
    {
        return true;
    }
    return load(csv_path);
}

const FuelModelRecord*
FuelModelRegistry::findByCode(const std::string& code) const
{
    auto it = records_.find(code);
    if (it == records_.end())
    {
        return nullptr;
    }
    return &it->second;
}

bool
FuelModelRegistry::load(const std::string& csv_path)
{
    std::ifstream input(csv_path);
    if (!input)
    {
        std::cerr << "FuelModelRegistry: unable to open " << csv_path << std::endl;
        loaded_ = false;
        return false;
    }

    std::string header;
    if (!std::getline(input, header))
    {
        std::cerr << "FuelModelRegistry: empty file " << csv_path << std::endl;
        loaded_ = false;
        return false;
    }

    std::unordered_map<std::string, FuelModelRecord> new_records;
    std::string line;
    while (std::getline(input, line))
    {
        line = trim(line);
        if (line.empty())
            continue;
        std::stringstream ss(line);
        std::string token;

        FuelModelRecord record{};
        std::string code;
        std::getline(ss, code, ',');
        code = trim(code);
        if (code.empty())
            continue;

        auto readFloat = [&]() -> float {
            std::string value;
            if (!std::getline(ss, value, ','))
                return 0.0f;
            return parseFloat(trim(value));
        };

        record.dead1 = readFloat();
        record.dead10 = readFloat();
        record.dead100 = readFloat();
        record.live_herb = readFloat();
        record.live_wood = readFloat();

        std::string type;
        if (!std::getline(ss, type, ','))
            type.clear();
        type = trim(type);
        record.dynamic = (type == "dynamic");

        record.sav_dead = readFloat();
        record.sav_live_herb = readFloat();
        record.sav_live_wood = readFloat();
        record.depth = readFloat();
        record.mext = readFloat();
        record.heat = readFloat();

        new_records[code] = record;
    }

    if (new_records.empty())
    {
        std::cerr << "FuelModelRegistry: no rows parsed from " << csv_path << std::endl;
        loaded_ = false;
        return false;
    }

    records_ = std::move(new_records);
    source_ = csv_path;
    loaded_ = true;
    std::cerr << "FuelModelRegistry: loaded " << records_.size() << " fuel models from " << csv_path
              << std::endl;
    return true;
}
