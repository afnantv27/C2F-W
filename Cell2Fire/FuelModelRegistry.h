#ifndef FUELMODELREGISTRY_H
#define FUELMODELREGISTRY_H

#include <string>
#include <unordered_map>

struct FuelModelRecord
{
    float dead1;
    float dead10;
    float dead100;
    float live_herb;
    float live_wood;
    float depth;
    float mext;
    float heat;
    float sav_dead;
    float sav_live_herb;
    float sav_live_wood;
    bool dynamic;
};

class FuelModelRegistry
{
  public:
    static FuelModelRegistry& instance();

    // Ensures the table at csv_path is loaded. Safe to call multiple times.
    bool ensureLoaded(const std::string& csv_path);

    const FuelModelRecord* findByCode(const std::string& code) const;
    const std::unordered_map<std::string, FuelModelRecord>& all() const { return records_; }
    const std::string& currentSource() const { return source_; }

  private:
    FuelModelRegistry() = default;
    FuelModelRegistry(const FuelModelRegistry&) = delete;
    FuelModelRegistry& operator=(const FuelModelRegistry&) = delete;

    bool load(const std::string& csv_path);

    bool loaded_ = false;
    std::string source_;
    std::unordered_map<std::string, FuelModelRecord> records_;
};

#endif // FUELMODELREGISTRY_H
