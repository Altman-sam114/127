#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"

ROOT = File.expand_path("..", __dir__)

SWIFT_GLOBS = [
  "WWIIHexV0/App/**/*.swift",
  "WWIIHexV0/UI/**/*.swift",
  "WWIIHexV0/SpriteKit/**/*.swift"
].freeze

SWIFT_MESSAGE_GLOBS = [
  "WWIIHexV0/Commands/**/*.swift",
  "WWIIHexV0/Rules/**/*.swift",
  "WWIIHexV0/Turn/**/*.swift",
  "WWIIHexV0/Agents/**/*.swift",
  "WWIIHexV0/Core/StrategicStateBootstrapper.swift"
].freeze

SWIFT_MESSAGE_EXCLUDES = [
  "WWIIHexV0/Agents/AgentConfiguration.swift",
  "WWIIHexV0/Agents/AgentPromptBuilder.swift"
].freeze

CORE_VISIBLE_SWIFT_FILES = [
  "WWIIHexV0/Core/Faction.swift",
  "WWIIHexV0/Core/GamePhase.swift",
  "WWIIHexV0/Core/MapDisplayLayer.swift",
  "WWIIHexV0/Core/EconomyState.swift",
  "WWIIHexV0/Core/Terrain.swift",
  "WWIIHexV0/Core/FireSupportState.swift",
  "WWIIHexV0/Core/DiplomacyState.swift",
  "WWIIHexV0/Core/OperationalAwarenessState.swift",
  "WWIIHexV0/Commands/Command.swift",
  "WWIIHexV0/Commands/RegionCommand.swift",
  "WWIIHexV0/Commands/WarDirective.swift",
  "WWIIHexV0/Agents/GameAgent.swift",
  "WWIIHexV0/Agents/ModernCommandChain.swift"
].freeze

JSON_FILES = [
  "WWIIHexV0/Data/grey_tide_2030_scenario.json",
  "WWIIHexV0/Data/grey_tide_2030_regions.json",
  "WWIIHexV0/Data/modern_unit_templates.json",
  "WWIIHexV0/Data/generals.json"
].freeze

VISIBLE_JSON_KEYS = %w[
  biography
  cityName
  dataNotes
  description
  displayName
  fortressName
  localizedName
  name
  rank
  summary
  title
].freeze

LEGACY_PATTERNS = [
  ["WWII", /WWII/i],
  ["World War", /World War/i],
  ["Ardennes", /Ardennes/i],
  ["Bastogne", /Bastogne/i],
  ["St Vith", /St\.?\s+Vith/i],
  ["Panzer", /Panzer/i],
  ["Guderian", /Guderian/i],
  ["Germany", /Germany/i],
  ["German", /German/i],
  ["Allies", /Allies/i],
  ["Allied", /Allied/i],
  ["Axis", /Axis/i],
  ["Wehrmacht", /Wehrmacht/i],
  ["Luftwaffe", /Luftwaffe/i],
  ["Nazi", /Nazi/i],
  ["Hitler", /Hitler/i],
  ["Third Reich", /Third Reich/i],
  ["Soviet", /Soviet/i],
  ["Province", /Province/i],
  ["Division", /Division/i],
  ["MockAI", /MockAI/],
  ["legacy supply marker", /\bSUP\s+[AG]\b/i],
  ["legacy IC label", /\bIC\b/],
  ["legacy Supplies label", /\bSupplies\b/i],
  ["legacy front zone label", /front zone/i],
  ["legacy ruler label", /\bruler\b/i],
  ["legacy theater label", /\btheater\b/i]
].freeze

# These literals are compatibility identifiers or internal provider ids. They are
# not displayed directly on the modern default UI path.
ALLOWED_SWIFT_LITERALS = [
  ["WWIIHexV0/App/AppContainer.swift", "MockAI"],
  ["WWIIHexV0/App/AppContainer.swift", "ardennes_v0"],
  ["WWIIHexV0/Rules/RegionVictoryRules.swift", "Bastogne"],
  ["WWIIHexV0/Rules/RegionVictoryRules.swift", "St. Vith"],
  ["WWIIHexV0/Rules/VictoryRules.swift", "Bastogne"],
  ["WWIIHexV0/Rules/VictoryRules.swift", "St. Vith"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "theater_1"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "theater_2"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "theater_3"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "theater_4"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "germany_front"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "germany_depth"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "germany_core"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "soviet_front"],
  ["WWIIHexV0/SpriteKit/MapLayerOverlayNode.swift", "soviet_depth"],
  ["WWIIHexV0/UI/AgentPanelView.swift", "MockAI"]
].freeze

def relative_path(path)
  path.sub("#{ROOT}/", "")
end

def swift_files
  SWIFT_GLOBS.flat_map { |pattern| Dir[File.join(ROOT, pattern)] }.sort
end

def swift_message_files
  excluded = SWIFT_MESSAGE_EXCLUDES.to_h { |rel| [File.join(ROOT, rel), true] }
  SWIFT_MESSAGE_GLOBS
    .flat_map { |pattern| Dir[File.join(ROOT, pattern)] }
    .uniq
    .reject { |path| excluded[path] }
    .sort
end

def scan_swift_string_literals(path)
  hits = []
  File.readlines(path).each_with_index do |line, index|
    line.scan(/"([^"\\]*(?:\\.[^"\\]*)*)"/) do |match|
      hits << [index + 1, match.first]
    end
  end
  hits
end

def scan_core_visible_string_literals(path)
  hits = []
  visible_block_depth = nil
  File.readlines(path).each_with_index do |line, index|
    if visible_block_depth.nil? && line.match?(/\bvar\s+(displayName|shortDisplayName)\s*:\s*String\s*\{/)
      visible_block_depth = 0
    end

    if visible_block_depth
      line.scan(/"([^"\\]*(?:\\.[^"\\]*)*)"/) do |match|
        hits << [index + 1, match.first]
      end

      visible_block_depth += line.count("{")
      visible_block_depth -= line.count("}")
      visible_block_depth = nil if visible_block_depth <= 0
    end
  end
  hits
end

def visible_json_path?(path)
  path.any? { |segment| segment.is_a?(String) && VISIBLE_JSON_KEYS.include?(segment) }
end

def walk_json(value, path, &block)
  case value
  when Hash
    value.each { |key, child| walk_json(child, path + [key], &block) }
  when Array
    value.each_with_index { |child, index| walk_json(child, path + [index], &block) }
  when String
    yield(path, value)
  end
end

def pattern_hits(value)
  visible_text = value.gsub(/\\\([^)]*\)/, " ")
  LEGACY_PATTERNS.select { |_label, pattern| visible_text.match?(pattern) }.map(&:first)
end

def allowed_swift_literal?(path, value)
  ALLOWED_SWIFT_LITERALS.any? do |allowed_path, allowed_value|
    allowed_path == path && allowed_value == value
  end
end

errors = []
swift_checked = 0
json_values_checked = 0
allowlisted = 0

swift_files.each do |path|
  rel = relative_path(path)
  scan_swift_string_literals(path).each do |line_number, value|
    hits = pattern_hits(value)
    next if hits.empty?

    if allowed_swift_literal?(rel, value)
      allowlisted += 1
      next
    end

    errors << "#{rel}:#{line_number}: #{hits.join(", ")} in Swift visible string literal: #{value.inspect}"
  end
  swift_checked += 1
end

swift_message_files.each do |path|
  rel = relative_path(path)
  scan_swift_string_literals(path).each do |line_number, value|
    hits = pattern_hits(value)
    next if hits.empty?

    if allowed_swift_literal?(rel, value)
      allowlisted += 1
      next
    end

    errors << "#{rel}:#{line_number}: #{hits.join(", ")} in Swift result/log string literal: #{value.inspect}"
  end
  swift_checked += 1
end

CORE_VISIBLE_SWIFT_FILES.each do |rel|
  path = File.join(ROOT, rel)
  scan_core_visible_string_literals(path).each do |line_number, value|
    hits = pattern_hits(value)
    next if hits.empty?

    errors << "#{rel}:#{line_number}: #{hits.join(", ")} in Core visible display string: #{value.inspect}"
  end
  swift_checked += 1
end

JSON_FILES.each do |rel|
  path = File.join(ROOT, rel)
  data = JSON.parse(File.read(path))
  walk_json(data, []) do |json_path, value|
    next unless visible_json_path?(json_path)

    json_values_checked += 1
    hits = pattern_hits(value)
    next if hits.empty?

    errors << "#{rel}:#{json_path.join(".")}: #{hits.join(", ")} in visible JSON value: #{value.inspect}"
  end
end

if errors.empty?
  puts "modern_visible_text ok: swiftFiles=#{swift_checked} jsonVisibleValues=#{json_values_checked} allowlisted=#{allowlisted}"
else
  warn "modern_visible_text failed:"
  errors.each { |error| warn "- #{error}" }
  exit 1
end
