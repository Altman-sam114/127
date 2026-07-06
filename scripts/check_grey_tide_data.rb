#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "set"

ROOT = File.expand_path("..", __dir__)
DATA_DIR = File.join(ROOT, "WWIIHexV0", "Data")
RULES_DIR = File.join(ROOT, "WWIIHexV0", "Rules")

def load_json(filename)
  JSON.parse(File.read(File.join(DATA_DIR, filename)))
end

def coord_key(coord)
  "#{coord.fetch("q")},#{coord.fetch("r")}"
end

def ensure_unique(errors, label, values)
  duplicates = values.group_by { |value| value }.select { |_value, hits| hits.size > 1 }.keys
  errors << "#{label} duplicates: #{duplicates.join(", ")}" unless duplicates.empty?
end

def ensure_same_set(errors, label, expected, actual)
  expected_set = expected.to_set
  actual_set = actual.to_set
  missing = expected_set - actual_set
  extra = actual_set - expected_set
  errors << "#{label} missing: #{missing.to_a.sort.join(", ")}" unless missing.empty?
  errors << "#{label} extra: #{extra.to_a.sort.join(", ")}" unless extra.empty?
end

def load_grey_tide_victory_rule_objectives
  source = File.read(File.join(RULES_DIR, "VictoryRules.swift"))
  match = source.match(/greyTideMainObjectiveIds:\s*Set<String>\s*=\s*\[(.*?)\]/m)
  raise "VictoryRules.greyTideMainObjectiveIds not found" unless match

  match[1].scan(/"([^"]+)"/).flatten
end

scenario = load_json("grey_tide_2030_scenario.json")
regions = load_json("grey_tide_2030_regions.json")
templates = load_json("modern_unit_templates.json")
victory_rule_main_objective_ids = load_grey_tide_victory_rule_objectives
errors = []
ensure_unique(errors, "VictoryRules main objective ids", victory_rule_main_objective_ids)

errors << "scenario id must be grey_tide_2030" unless scenario["id"] == "grey_tide_2030"
errors << "regions scenarioId must be grey_tide_2030" unless regions["scenarioId"] == "grey_tide_2030"

factions = scenario.fetch("factions").to_set
tiles = scenario.fetch("map").fetch("tiles")
tile_keys = tiles.map { |tile| coord_key(tile) }
tile_key_set = tile_keys.to_set
ensure_unique(errors, "tile coords", tile_keys)

width = scenario.fetch("map").fetch("width")
height = scenario.fetch("map").fetch("height")
unless scenario.fetch("map").fetch("isSparse")
  expected_tile_count = width * height
  errors << "tile count #{tiles.size} != width*height #{expected_tile_count}" unless tiles.size == expected_tile_count
end

tiles.each do |tile|
  key = coord_key(tile)
  q = tile.fetch("q")
  r = tile.fetch("r")
  errors << "tile #{key} q out of bounds" unless q.between?(0, width - 1)
  errors << "tile #{key} r out of bounds" unless r.between?(0, height - 1)
  controller = tile["controller"]
  errors << "tile #{key} controller #{controller} missing from factions" if controller && !factions.include?(controller)
  supply_faction = tile["supplyFaction"]
  errors << "tile #{key} supply source missing supplyFaction" if tile["isSupplySource"] && !supply_faction
  if supply_faction && !factions.include?(supply_faction)
    errors << "tile #{key} supplyFaction #{supply_faction} missing from factions"
  end
end

template_ids = templates.fetch("templates").map { |template| template.fetch("id") }
template_id_set = template_ids.to_set
ensure_unique(errors, "template ids", template_ids)
templates.fetch("templates").each do |template|
  errors << "template #{template["id"]} maxHP must be positive" unless template.fetch("maxHP").positive?
  errors << "template #{template["id"]} missing components" if template.fetch("components").empty?
end

objective_ids = scenario.fetch("objectives").map { |objective| objective.fetch("id") }
objective_id_set = objective_ids.to_set
ensure_unique(errors, "objective ids", objective_ids)
scenario.fetch("objectives").each do |objective|
  key = coord_key(objective.fetch("coord"))
  errors << "objective #{objective["id"]} coord #{key} missing tile" unless tile_key_set.include?(key)
end

scenario.fetch("keyLocations").each do |location|
  key = coord_key(location.fetch("coord"))
  errors << "key location #{location["id"]} coord #{key} missing tile" unless tile_key_set.include?(key)
  faction = location["faction"]
  errors << "key location #{location["id"]} faction #{faction} missing from factions" if faction && !factions.include?(faction)
  objective_id = location["objectiveId"]
  errors << "key location #{location["id"]} objective #{objective_id} missing" if objective_id && !objective_id_set.include?(objective_id)
end

unit_ids = scenario.fetch("initialUnits").map { |unit| unit.fetch("id") }
ensure_unique(errors, "initial unit ids", unit_ids)
scenario.fetch("initialUnits").each do |unit|
  key = coord_key(unit.fetch("coord"))
  errors << "unit #{unit["id"]} coord #{key} missing tile" unless tile_key_set.include?(key)
  errors << "unit #{unit["id"]} faction #{unit["faction"]} missing from factions" unless factions.include?(unit.fetch("faction"))
  errors << "unit #{unit["id"]} template #{unit["templateId"]} missing" unless template_id_set.include?(unit.fetch("templateId"))
end

region_ids = regions.fetch("regions").map { |region| region.fetch("id") }
region_id_set = region_ids.to_set
regions_by_id = regions.fetch("regions").to_h { |region| [region.fetch("id"), region] }
ensure_unique(errors, "region ids", region_ids)

hex_to_region = regions.fetch("hexToRegion")
hex_to_region.each do |key, region_id|
  errors << "hexToRegion #{key} missing tile" unless tile_key_set.include?(key)
  errors << "hexToRegion #{key} region #{region_id} missing" unless region_id_set.include?(region_id)
end

tiles.each do |tile|
  key = coord_key(tile)
  region_id = tile["regionId"]
  errors << "tile #{key} missing regionId" unless region_id
  errors << "tile #{key} region #{region_id} missing" if region_id && !region_id_set.include?(region_id)
  mapped_region_id = hex_to_region[key]
  errors << "tile #{key} missing hexToRegion mapping" unless mapped_region_id
  if region_id && mapped_region_id && region_id != mapped_region_id
    errors << "tile #{key} regionId #{region_id} != hexToRegion #{mapped_region_id}"
  end
  objective_id = tile["objectiveId"]
  errors << "tile #{key} objective #{objective_id} missing" if objective_id && !objective_id_set.include?(objective_id)
end

regions.fetch("regions").each do |region|
  region_id = region.fetch("id")
  owner = region["owner"]
  controller = region["controller"]
  errors << "region #{region_id} owner #{owner} missing from factions" if owner && !factions.include?(owner)
  errors << "region #{region_id} controller #{controller} missing from factions" if controller && !factions.include?(controller)
  region.fetch("coreOf").each do |faction|
    errors << "region #{region_id} coreOf #{faction} missing from factions" unless factions.include?(faction)
  end
  region.fetch("displayHexes").each do |coord|
    key = coord_key(coord)
    errors << "region #{region_id} displayHex #{key} missing tile" unless tile_key_set.include?(key)
    mapped_region_id = hex_to_region[key]
    errors << "region #{region_id} displayHex #{key} maps to #{mapped_region_id}" if mapped_region_id && mapped_region_id != region_id
  end
  representative_key = coord_key(region.fetch("representativeHex"))
  errors << "region #{region_id} representativeHex #{representative_key} missing tile" unless tile_key_set.include?(representative_key)
  region.fetch("neighbors").each do |neighbor_id|
    errors << "region #{region_id} neighbor #{neighbor_id} missing" unless region_id_set.include?(neighbor_id)
    next unless regions_by_id[neighbor_id]

    unless regions_by_id[neighbor_id].fetch("neighbors").include?(region_id)
      errors << "region #{region_id} neighbor #{neighbor_id} is not symmetric"
    end
  end
end

regions.fetch("edges").each do |edge|
  from = edge.fetch("from")
  to = edge.fetch("to")
  errors << "edge from #{from} missing" unless region_id_set.include?(from)
  errors << "edge to #{to} missing" unless region_id_set.include?(to)
end

regions.fetch("supplySources").each do |source|
  region_id = source.fetch("regionId")
  faction = source["faction"]
  errors << "region supply #{source["id"]} region #{region_id} missing" unless region_id_set.include?(region_id)
  errors << "region supply #{source["id"]} faction #{faction} missing from factions" if faction && !factions.include?(faction)
end

region_objective_ids = regions.fetch("objectives").map { |objective| objective.fetch("id") }
region_objective_id_set = region_objective_ids.to_set
region_main_objective_ids = regions.fetch("objectives")
  .select { |objective| objective["mainObjective"] }
  .map { |objective| objective.fetch("id") }
ensure_unique(errors, "region objective ids", region_objective_ids)
regions.fetch("objectives").each do |objective|
  objective_id = objective.fetch("id")
  region_id = objective.fetch("regionId")
  errors << "region objective #{objective_id} missing from scenario objectives" unless objective_id_set.include?(objective_id)
  errors << "region objective #{objective_id} region #{region_id} missing" unless region_id_set.include?(region_id)
end
objective_ids.each do |objective_id|
  errors << "scenario objective #{objective_id} missing from region objectives" unless region_objective_id_set.include?(objective_id)
end
victory_rule_main_objective_ids.each do |objective_id|
  errors << "VictoryRules main objective #{objective_id} missing from scenario objectives" unless objective_id_set.include?(objective_id)
  errors << "VictoryRules main objective #{objective_id} missing from region objectives" unless region_objective_id_set.include?(objective_id)
end
ensure_same_set(errors, "region main objectives vs VictoryRules", victory_rule_main_objective_ids, region_main_objective_ids)

scenario.fetch("victoryConditions").each do |condition|
  faction = condition["faction"]
  target_faction = condition["targetFaction"]
  errors << "victory #{condition["id"]} faction #{faction} missing from factions" if faction && !factions.include?(faction)
  if target_faction && !factions.include?(target_faction)
    errors << "victory #{condition["id"]} targetFaction #{target_faction} missing from factions"
  end
  Array(condition["objectiveIds"]).each do |objective_id|
    errors << "victory #{condition["id"]} objective #{objective_id} missing" unless objective_id_set.include?(objective_id)
  end
end

main_victory_condition_ids = [
  "vc_blue_key_nodes",
  "vc_red_defense_network"
]
victory_conditions_by_id = scenario.fetch("victoryConditions").to_h { |condition| [condition.fetch("id"), condition] }
main_victory_condition_ids.each do |condition_id|
  condition = victory_conditions_by_id[condition_id]
  unless condition
    errors << "victory #{condition_id} missing"
    next
  end
  ensure_same_set(
    errors,
    "victory #{condition_id} objectives vs VictoryRules",
    victory_rule_main_objective_ids,
    Array(condition["objectiveIds"])
  )
end

if errors.empty?
  puts "grey_tide_data ok: tiles=#{tiles.size} regions=#{region_ids.size} units=#{unit_ids.size} objectives=#{objective_ids.size} mainObjectives=#{victory_rule_main_objective_ids.size} templates=#{template_ids.size}"
  exit 0
end

warn "grey_tide_data failed:"
errors.each { |error| warn "- #{error}" }
exit 1
