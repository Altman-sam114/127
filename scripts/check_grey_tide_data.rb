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

def edge_key(from, to)
  [from, to].sort.join(" <-> ")
end

def hex_neighbor_keys(key)
  q, r = key.split(",").map(&:to_i)
  [
    [q + 1, r],
    [q + 1, r - 1],
    [q, r - 1],
    [q - 1, r],
    [q - 1, r + 1],
    [q, r + 1]
  ].map { |neighbor_q, neighbor_r| "#{neighbor_q},#{neighbor_r}" }
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
ensure_same_set(errors, "grey_tide factions", ["blueForce", "redForce", "neutral"], factions.to_a)
errors << "playerFaction must be blueForce" unless scenario["playerFaction"] == "blueForce"
errors << "aiFaction must be redForce" unless scenario["aiFaction"] == "redForce"
errors << "initialPhase must be blueCommand" unless scenario["initialPhase"] == "blueCommand"

tiles = scenario.fetch("map").fetch("tiles")
tile_keys = tiles.map { |tile| coord_key(tile) }
tile_key_set = tile_keys.to_set
tiles_by_key = tiles.to_h { |tile| [coord_key(tile), tile] }
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
templates_by_id = templates.fetch("templates").to_h { |template| [template.fetch("id"), template] }
ensure_unique(errors, "template ids", template_ids)
templates.fetch("templates").each do |template|
  errors << "template #{template["id"]} maxHP must be positive" unless template.fetch("maxHP").positive?
  errors << "template #{template["id"]} missing components" if template.fetch("components").empty?
end

objective_ids = scenario.fetch("objectives").map { |objective| objective.fetch("id") }
objective_id_set = objective_ids.to_set
objectives_by_id = scenario.fetch("objectives").to_h { |objective| [objective.fetch("id"), objective] }
ensure_unique(errors, "objective ids", objective_ids)
scenario.fetch("objectives").each do |objective|
  key = coord_key(objective.fetch("coord"))
  tile = tiles_by_key[key]
  errors << "objective #{objective["id"]} coord #{key} missing tile" unless tile
  if tile && tile["objectiveId"] != objective["id"]
    errors << "objective #{objective["id"]} coord #{key} tile objectiveId #{tile["objectiveId"] || "nil"}"
  end
end

key_location_ids = scenario.fetch("keyLocations").map { |location| location.fetch("id") }
ensure_unique(errors, "key location ids", key_location_ids)
linked_key_location_objective_ids = []
scenario.fetch("keyLocations").each do |location|
  key = coord_key(location.fetch("coord"))
  errors << "key location #{location["id"]} coord #{key} missing tile" unless tile_key_set.include?(key)
  faction = location["faction"]
  errors << "key location #{location["id"]} faction #{faction} missing from factions" if faction && !factions.include?(faction)
  objective_id = location["objectiveId"]
  errors << "key location #{location["id"]} objective #{objective_id} missing" if objective_id && !objective_id_set.include?(objective_id)
  next unless objective_id && objective_id_set.include?(objective_id)

  linked_key_location_objective_ids << objective_id
  objective = objectives_by_id.fetch(objective_id)
  objective_key = coord_key(objective.fetch("coord"))
  if objective_key != key
    errors << "key location #{location["id"]} coord #{key} != objective #{objective_id} coord #{objective_key}"
  end
  if location["name"] != objective["name"]
    errors << "key location #{location["id"]} name #{location["name"]} != objective #{objective_id} name #{objective["name"]}"
  end
end
ensure_unique(errors, "key location objective ids", linked_key_location_objective_ids)
ensure_same_set(errors, "key location objectives vs scenario objectives", objective_ids, linked_key_location_objective_ids)

unit_ids = scenario.fetch("initialUnits").map { |unit| unit.fetch("id") }
unit_coord_keys = scenario.fetch("initialUnits").map { |unit| coord_key(unit.fetch("coord")) }
ensure_unique(errors, "initial unit ids", unit_ids)
ensure_unique(errors, "initial unit coords", unit_coord_keys)
scenario.fetch("initialUnits").each do |unit|
  key = coord_key(unit.fetch("coord"))
  tile = tiles_by_key[key]
  errors << "unit #{unit["id"]} coord #{key} missing tile" unless tile
  unit_faction = unit.fetch("faction")
  errors << "unit #{unit["id"]} faction #{unit_faction} missing from factions" unless factions.include?(unit_faction)
  template_id = unit.fetch("templateId")
  template = templates_by_id[template_id]
  errors << "unit #{unit["id"]} template #{template_id} missing" unless template
  hp = unit.fetch("hp")
  if template
    errors << "unit #{unit["id"]} hp #{hp} outside 1..#{template.fetch("maxHP")}" unless hp.between?(1, template.fetch("maxHP"))
  end
  unless %w[east northEast northWest west southWest southEast].include?(unit.fetch("facing"))
    errors << "unit #{unit["id"]} facing #{unit["facing"]} invalid"
  end
  unless %w[supplied lowSupply encircled].include?(unit.fetch("supplyState"))
    errors << "unit #{unit["id"]} supplyState #{unit["supplyState"]} invalid"
  end
  unless %w[retreatable hold].include?(unit.fetch("retreatMode"))
    errors << "unit #{unit["id"]} retreatMode #{unit["retreatMode"]} invalid"
  end
  next unless tile

  tile_controller = tile["controller"]
  if tile_controller && !["neutral", unit_faction].include?(tile_controller)
    errors << "unit #{unit["id"]} starts on hostile-controlled tile #{key} controller #{tile_controller}"
  end
end

region_ids = regions.fetch("regions").map { |region| region.fetch("id") }
region_id_set = region_ids.to_set
regions_by_id = regions.fetch("regions").to_h { |region| [region.fetch("id"), region] }
ensure_unique(errors, "region ids", region_ids)

scenario.fetch("initialUnits").each do |unit|
  key = coord_key(unit.fetch("coord"))
  tile = tiles_by_key[key]
  next unless tile

  unit_faction = unit.fetch("faction")
  region_id = tile["regionId"]
  region = regions_by_id[region_id]
  region_controller = region && region["controller"]
  if region_controller && !["neutral", unit_faction].include?(region_controller)
    errors << "unit #{unit["id"]} starts in hostile-controlled region #{region_id} controller #{region_controller}"
  end
end

hex_to_region = regions.fetch("hexToRegion")
hex_to_region.each do |key, region_id|
  errors << "hexToRegion #{key} missing tile" unless tile_key_set.include?(key)
  errors << "hexToRegion #{key} region #{region_id} missing" unless region_id_set.include?(region_id)
end

tile_controller_majority_by_region = tiles
  .group_by { |tile| tile.fetch("regionId") }
  .transform_values do |region_tiles|
  region_tiles
    .map { |tile| tile["controller"] }
    .compact
    .group_by { |controller| controller }
    .transform_values(&:size)
    .max_by { |faction, count| [count, faction] }
    &.first
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
  errors << "region #{region_id} supplyValue must be positive" unless region.fetch("supplyValue").positive?
  majority_controller = tile_controller_majority_by_region[region_id]
  if controller && majority_controller && controller != majority_controller
    errors << "region #{region_id} controller #{controller} != tile majority #{majority_controller}"
  end
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

neighbor_edge_keys = regions.fetch("regions").flat_map do |region|
  region.fetch("neighbors").map { |neighbor_id| edge_key(region.fetch("id"), neighbor_id) }
end.uniq
declared_edge_keys = regions.fetch("edges").map { |edge| edge_key(edge.fetch("from"), edge.fetch("to")) }
ensure_unique(errors, "region edge pairs", declared_edge_keys)
ensure_same_set(errors, "region edges vs neighbors", neighbor_edge_keys, declared_edge_keys)

real_hex_edge_keys = hex_to_region.flat_map do |key, region_id|
  hex_neighbor_keys(key).map do |neighbor_key|
    neighbor_region_id = hex_to_region[neighbor_key]
    next if neighbor_region_id.nil? || neighbor_region_id == region_id

    edge_key(region_id, neighbor_region_id)
  end.compact
end.to_set

regions.fetch("edges").each do |edge|
  from = edge.fetch("from")
  to = edge.fetch("to")
  key = edge_key(from, to)
  errors << "edge from #{from} missing" unless region_id_set.include?(from)
  errors << "edge to #{to} missing" unless region_id_set.include?(to)
  errors << "edge #{key} has no real adjacent hex pair" unless real_hex_edge_keys.include?(key)
  if regions_by_id[from] && !regions_by_id[from].fetch("neighbors").include?(to)
    errors << "edge #{from} -> #{to} missing from #{from} neighbors"
  end
  if regions_by_id[to] && !regions_by_id[to].fetch("neighbors").include?(from)
    errors << "edge #{from} -> #{to} missing from #{to} neighbors"
  end
end

tile_supply_sources_by_region_faction = tiles
  .select { |tile| tile["isSupplySource"] }
  .group_by { |tile| [tile.fetch("regionId"), tile.fetch("supplyFaction")] }

regions.fetch("supplySources").each do |source|
  region_id = source.fetch("regionId")
  faction = source["faction"]
  errors << "region supply #{source["id"]} region #{region_id} missing" unless region_id_set.include?(region_id)
  errors << "region supply #{source["id"]} faction #{faction} missing from factions" if faction && !factions.include?(faction)
  region = regions_by_id[region_id]
  if region && faction
    unless region.fetch("supplyValue").positive?
      errors << "region supply #{source["id"]} region #{region_id} supplyValue must be positive"
    end
    unless region["controller"] == faction
      errors << "region supply #{source["id"]} region #{region_id} controller #{region["controller"]} conflicts with faction #{faction}"
    end
    unless tile_supply_sources_by_region_faction.key?([region_id, faction])
      errors << "region supply #{source["id"]} has no matching tile supply source in #{region_id} for #{faction}"
    end
  end
end

tiles.select { |tile| tile["isSupplySource"] }.each do |tile|
  key = coord_key(tile)
  region_id = tile.fetch("regionId")
  supply_faction = tile.fetch("supplyFaction")
  controller = tile["controller"]
  if controller && controller != supply_faction
    errors << "tile supply source #{key} controller #{controller} != supplyFaction #{supply_faction}"
  end
  unless regions.fetch("supplySources").any? { |source| source["regionId"] == region_id && source["faction"] == supply_faction }
    errors << "tile supply source #{key} missing matching region supply source for #{region_id} #{supply_faction}"
  end
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
  scenario_objective = objectives_by_id[objective_id]
  next unless scenario_objective

  scenario_objective_key = coord_key(scenario_objective.fetch("coord"))
  mapped_region_id = hex_to_region[scenario_objective_key]
  if mapped_region_id && mapped_region_id != region_id
    errors << "region objective #{objective_id} region #{region_id} != objective coord region #{mapped_region_id}"
  end
  if objective["type"] != scenario_objective["kind"]
    errors << "region objective #{objective_id} type #{objective["type"]} != scenario kind #{scenario_objective["kind"]}"
  end
  if objective["victoryPoints"] != scenario_objective["points"]
    errors << "region objective #{objective_id} victoryPoints #{objective["victoryPoints"]} != scenario points #{scenario_objective["points"]}"
  end
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
