/*
===========================================================================

  Copyright (c) 2026 LandSandBoat Dev Teams

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see http://www.gnu.org/licenses/

===========================================================================
*/

#include "data/enums/detects.h"
#include "map/data/datasets/ecosystems/dataset.h"
#include "map/data/datasets/stats/yaml.h"
#include "map/data/datasets/status_effects/dataset.h"
#include "map/data/datasets/status_effects/yaml.h"
#include "map/data/yaml/merge.h"

#include <catch2/catch_test_macros.hpp>

#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <variant>
#include <vector>

using EcosystemsDataset   = xi::data::datasets::ecosystems::Dataset;
using StatusEffectDataset = xi::data::datasets::status_effects::Dataset;

TEST_CASE("data binding: status schema preserves signed defaults and bounds", "[data][schema]")
{
    using Effect = xi::data::datasets::status_effects::wire::StatusEffect;
    const glz::json_schema<Effect> annotations{};
    const std::array               entries{ &annotations.min_duration, &annotations.sort_key, &annotations.wear_off_message_id };
    for (const auto* entry : entries)
    {
        REQUIRE(entry->defaultValue.has_value());
        REQUIRE(std::holds_alternative<std::int64_t>(*entry->defaultValue));
        CHECK(std::get<std::int64_t>(*entry->defaultValue) == 0);
        REQUIRE(entry->minimum.has_value());
        REQUIRE(entry->maximum.has_value());
        REQUIRE(std::holds_alternative<std::int64_t>(*entry->minimum));
        REQUIRE(std::holds_alternative<std::int64_t>(*entry->maximum));
        CHECK(std::get<std::int64_t>(*entry->minimum) == 0);
        CHECK(std::get<std::int64_t>(*entry->maximum) == 65535);
    }

    const auto encoded = glz::write_json_schema<Effect, glz::opts{ .error_on_missing_keys = true }>();
    REQUIRE(encoded.has_value());
    glz::generic decoded;
    REQUIRE_FALSE(glz::read_json(decoded, *encoded));
    using Object     = glz::generic::object_t;
    const auto* root = decoded.get_if<Object>();
    REQUIRE(root != nullptr);
    REQUIRE(root->contains("properties"));
    const auto* properties = root->at("properties").get_if<Object>();
    REQUIRE(properties != nullptr);
    for (const auto* field : { "min_duration", "sort_key", "wear_off_message_id" })
    {
        CAPTURE(field);
        REQUIRE(properties->contains(field));
        const auto* schema = properties->at(field).get_if<Object>();
        REQUIRE(schema != nullptr);
        for (const auto* key : { "default", "minimum", "maximum" })
        {
            CAPTURE(key);
            REQUIRE(schema->contains(key));
            const auto* number = schema->at(key).get_if<double>();
            REQUIRE(number != nullptr);
            CHECK(*number == (std::string_view(key) == "maximum" ? 65535.0 : 0.0));
        }
    }

    REQUIRE(root->contains("$defs"));
    const auto* definitions = root->at("$defs").get_if<Object>();
    REQUIRE(definitions != nullptr);
    CHECK(definitions->contains(std::string(glz::name_v<uint16>)));
    CHECK_FALSE(definitions->contains(std::string(glz::name_v<std::optional<uint16>>)));
    const auto* minimum = properties->at("min_duration").get_if<Object>();
    REQUIRE(minimum != nullptr);
    REQUIRE(minimum->contains("anyOf"));
    const auto* alternatives = minimum->at("anyOf").get_if<glz::generic::array_t>();
    REQUIRE(alternatives != nullptr);
    REQUIRE(alternatives->size() == 2);
    const auto* reference = alternatives->at(0).get_if<Object>();
    REQUIRE(reference != nullptr);
    REQUIRE(reference->contains("$ref"));
    const auto* referenceName = reference->at("$ref").get_if<std::string>();
    REQUIRE(referenceName != nullptr);
    CHECK(*referenceName == "#/$defs/" + std::string(glz::name_v<uint16>));
    const auto* nullable = alternatives->at(1).get_if<Object>();
    REQUIRE(nullable != nullptr);
    REQUIRE(nullable->contains("type"));
    const auto* nullableType = nullable->at("type").get_if<std::string>();
    REQUIRE(nullableType != nullptr);
    CHECK(*nullableType == "null");
}

TEST_CASE("data binding: stats schema preserves payload keys and nested fields", "[data][schema]")
{
    using namespace xi::data::datasets::stats::wire;
    static_assert(glz::get_name<&Document::stats>() == "stats");
    static_assert(glz::reflect<Document>::size == 2);
    static_assert(glz::reflect<Document>::keys[0] == "meta");
    static_assert(glz::reflect<Document>::keys[1] == "stats");

    const auto encoded = glz::write_json_schema<Document, glz::opts{ .error_on_missing_keys = true }>();
    REQUIRE(encoded.has_value());
    glz::generic decoded;
    REQUIRE_FALSE(glz::read_json(decoded, *encoded));
    using Object     = glz::generic::object_t;
    const auto* root = decoded.get_if<Object>();
    REQUIRE(root != nullptr);
    REQUIRE(root->contains("properties"));
    const auto* properties = root->at("properties").get_if<Object>();
    REQUIRE(properties != nullptr);
    REQUIRE(properties->size() == 2);
    CHECK(properties->contains("meta"));
    REQUIRE(properties->contains("stats"));
    REQUIRE(root->contains("required"));
    const auto* required = root->at("required").get_if<glz::generic::array_t>();
    REQUIRE(required != nullptr);
    REQUIRE(required->size() == 1);
    const auto* payloadName = required->at(0).get_if<std::string>();
    REQUIRE(payloadName != nullptr);
    CHECK(*payloadName == "stats");

    const auto* payload = properties->at("stats").get_if<Object>();
    REQUIRE(payload != nullptr);
    REQUIRE(payload->contains("properties"));
    const auto* fields = payload->at("properties").get_if<Object>();
    REQUIRE(fields != nullptr);
    REQUIRE(fields->size() == 5);
    for (const auto* field : { "round_once", "hp", "mp", "attributes", "ungraded" })
    {
        CAPTURE(field);
        CHECK(fields->contains(field));
    }

    REQUIRE(root->contains("$defs"));
    const auto* definitions = root->at("$defs").get_if<Object>();
    REQUIRE(definitions != nullptr);
    const auto curveName = std::string(glz::name_v<Curve<GradeRow>>);
    REQUIRE(definitions->contains(curveName));
    const auto* curve = definitions->at(curveName).get_if<Object>();
    REQUIRE(curve != nullptr);
    REQUIRE(curve->contains("additionalProperties"));
    const auto* row = curve->at("additionalProperties").get_if<Object>();
    REQUIRE(row != nullptr);
    REQUIRE(row->contains("properties"));
    const auto* columns = row->at("properties").get_if<Object>();
    REQUIRE(columns != nullptr);
    REQUIRE(columns->size() == 7);
    for (const auto* column : { "a", "b", "c", "d", "e", "f", "g" })
    {
        CAPTURE(column);
        CHECK(columns->contains(column));
    }
}

TEST_CASE("data binding: modules keep sparse-map and list-replacement semantics", "[data][binding]")
{
    const std::string              core = R"(
status_effects:
  sample:
    id: 42
    flags:
      - damage
      - death
    min_duration: 5
)";
    const std::vector<std::string> modules{ R"(
status_effects:
  sample:
    flags:
      - no_cancel
)" };

    const auto  decoded = StatusEffectDataset::decode(xi::data::mergeYaml(core, modules));
    const auto& sample  = decoded.at(42);
    CHECK(sample.MinDuration == 5);
    CHECK(sample.Flags == xi::StatusEffectFlag::NoCancel);

    const std::string              ecosystemsCore = R"(
ecosystems:
  module_ecosystem:
    id: 250
    attributes:
      element: fire
      detects:
        - sight
        - hearing
      speed: 40
)";
    const std::vector<std::string> ecosystemsModules{ R"(
ecosystems:
  module_ecosystem:
    attributes:
      detects:
        - hearing
      speed: 32
)" };

    const auto  ecosystems = EcosystemsDataset::decode(xi::data::mergeYaml(ecosystemsCore, ecosystemsModules));
    const auto& attributes = ecosystems.at(static_cast<xi::Ecosystem>(250)).MobAttributes;
    CHECK(attributes.Element == xi::Element::Fire);
    CHECK(attributes.Detects == xi::Detects::Hearing);
    CHECK(attributes.Speed == 32);
}

TEST_CASE("data binding: runtime decoding is strict", "[data][binding]")
{
    CHECK_THROWS(StatusEffectDataset::decode(R"(
status_effects:
  sample:
    id: 42
    surprise: true
)"));

    CHECK_THROWS(StatusEffectDataset::decode(R"(
status_effects:
  sample:
    name: missing_id
)"));

    CHECK_THROWS(StatusEffectDataset::decode(R"(
status_effects:
  sample:
    id: 42
    element: definitely_not_an_element
)"));

    CHECK_THROWS(StatusEffectDataset::decode(R"(
status_effects:
  ko:
    id: 1
)"));

    CHECK_THROWS(StatusEffectDataset::decode(R"(
status_effects:
  invalid-name:
    id: 42
)"));

    CHECK_THROWS(StatusEffectDataset::decode(R"(
status_effects:
  sample:
    id: 42
    flags:
      - damage
      - damage
)"));

    CHECK_THROWS(EcosystemsDataset::decode(R"(
ecosystems:
  module_ecosystem:
    id: 250
    families:
      module_family:
        id: 0
)"));

    CHECK_THROWS(EcosystemsDataset::decode(R"(
ecosystems:
  module_ecosystem:
    id: 250
    speed: 32
)"));

    CHECK_THROWS(EcosystemsDataset::decode(R"(
ecosystems:
  module_ecosystem:
    id: 250
    attributes:
      stats:
        intelligence: a
)"));
}

TEST_CASE("data binding: explicit null clears optional values", "[data][binding]")
{
    const auto base = StatusEffectDataset::decode(xi::data::mergeYaml(R"(
status_effects:
  sample:
    id: 42
    name: null
    min_duration: null
)",
                                                                      {}));
    CHECK(base.at(42).Name == "sample");
    CHECK(base.at(42).MinDuration == 0);

    const std::vector<std::string> modules{ R"(
status_effects:
  sample:
    min_duration: null
)" };
    const auto                     overlaid = StatusEffectDataset::decode(xi::data::mergeYaml(R"(
status_effects:
  sample:
    id: 42
    min_duration: 5
)",
                                                                                              modules));
    CHECK(overlaid.at(42).MinDuration == 0);

    const std::vector<std::string> ecosystemsModules{ R"(
ecosystems:
  module_ecosystem:
    attributes: null
)" };
    const auto                     ecosystems = EcosystemsDataset::decode(xi::data::mergeYaml(R"(
ecosystems:
  module_ecosystem:
    id: 250
    attributes:
      speed: 32
)",
                                                                                              ecosystemsModules));
    CHECK_FALSE(ecosystems.at(static_cast<xi::Ecosystem>(250)).MobAttributes.Speed.has_value());
}

TEST_CASE("data binding: numeric IDs are authoritative and unique", "[data][binding]")
{
    CHECK_THROWS(StatusEffectDataset::decode(R"(
status_effects:
  first:
    id: 42
  second:
    id: 42
)"));

    const auto ecosystems = EcosystemsDataset::decode(R"(
ecosystems:
  module_defined_name:
    id: 250
    attributes:
      speed: 0
      charmable: false
      element: none
    families:
      another_module_name:
        id: 65000
        species:
          final_module_name:
            id: 64999
            attributes:
              detects:
                - hearing
      second_module_name:
        id: 64998
)");

    const auto  ecosystemId = static_cast<xi::Ecosystem>(250);
    const auto  familyId    = static_cast<xi::Family>(65000);
    const auto  speciesId   = static_cast<xi::Species>(64999);
    const auto& ecosystem   = ecosystems.at(ecosystemId);
    REQUIRE(ecosystem.MobAttributes.Speed.has_value());
    CHECK(*ecosystem.MobAttributes.Speed == 0);
    REQUIRE(ecosystem.MobAttributes.Charmable.has_value());
    CHECK_FALSE(*ecosystem.MobAttributes.Charmable);
    REQUIRE(ecosystem.MobAttributes.Element.has_value());
    CHECK(*ecosystem.MobAttributes.Element == xi::Element::None);
    CHECK(ecosystem.Families.size() == 2);
    CHECK(ecosystem.Families.at(familyId).Species.at(speciesId).MobAttributes.Detects == xi::Detects::Hearing);

    CHECK_THROWS(EcosystemsDataset::decode(R"(
ecosystems:
  first:
    id: 1
  second:
    id: 1
)"));
}

TEST_CASE("data binding: every stat-rank field resolves by name", "[data][binding]")
{
    const auto ecosystems = EcosystemsDataset::decode(R"(
ecosystems:
  module_ecosystem:
    id: 250
    attributes:
      stats:
        str: a
        dex: b
        vit: c
        agi: d
        int: e
        mnd: f
        chr: g
        def: a
        eva: b
        att: c
        acc: d
)");

    const auto& overrides = ecosystems.at(static_cast<xi::Ecosystem>(250)).MobAttributes;
    REQUIRE(overrides.Stats.has_value());
    const auto& ranks = *overrides.Stats;
    CHECK(ranks.Str == xi::StatRank::A);
    CHECK(ranks.Dex == xi::StatRank::B);
    CHECK(ranks.Vit == xi::StatRank::C);
    CHECK(ranks.Agi == xi::StatRank::D);
    CHECK(ranks.Int == xi::StatRank::E);
    CHECK(ranks.Mnd == xi::StatRank::F);
    CHECK(ranks.Chr == xi::StatRank::G);
    CHECK(ranks.Def == xi::StatRank::A);
    CHECK(ranks.Eva == xi::StatRank::B);
    CHECK(ranks.Att == xi::StatRank::C);
    CHECK(ranks.Acc == xi::StatRank::D);
}
