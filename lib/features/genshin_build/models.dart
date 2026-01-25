// lib/features/genshin_build/models.dart

class PillData {
  final String text;
  final String iconUrl;
  const PillData({required this.text, required this.iconUrl});
}

class IconNameData {
  final String name;
  final String iconUrl;
  const IconNameData({required this.name, required this.iconUrl});
}

class RankedData {
  final int rank;
  final String name;
  final String iconUrl;
  final int? count;
  const RankedData({
    required this.rank,
    required this.name,
    required this.iconUrl,
    this.count,
  });
}

class TableImage {
  final String url;
  final int? count;
  const TableImage({required this.url, this.count});
}

class AscensionCell {
  final String text;
  final TableImage? image;
  const AscensionCell({required this.text, this.image});
}

class AscensionTableData {
  final List<String> headers;
  final List<List<AscensionCell>> rows;
  const AscensionTableData({required this.headers, required this.rows});
}

/// ✅ Talents / Passives / Constellations 用
class SkillItemData {
  final String title;       // Normal Attack / Ascension 1 / Constellation 1 ...
  final String name;        // Sharpshooter ...
  final String iconUrl;
  final String description; // 文章
  const SkillItemData({
    required this.title,
    required this.name,
    required this.iconUrl,
    required this.description,
  });
}

class SkillGroupData {
  final String id;          // talents / passives / constellations
  final String title;       // Amber Talents ...
  final List<SkillItemData> items;
  const SkillGroupData({
    required this.id,
    required this.title,
    required this.items,
  });
}

class CharacterPageData {
  final String showcaseVideoId;
  final String name;
  final String portraitUrl;

  final List<PillData> pills;
  final List<IconNameData> materials;

  final List<RankedData> bestWeapons;
  final List<RankedData> bestArtifacts;

  final List<String> bestStatsLines;
  final AscensionTableData? ascension;

  /// ✅ 追加
  final List<SkillGroupData> skillGroups;

  const CharacterPageData({
    this.showcaseVideoId = '',
    required this.name,
    required this.portraitUrl,
    required this.pills,
    required this.materials,
    required this.bestWeapons,
    required this.bestArtifacts,
    required this.bestStatsLines,
    required this.ascension,
    required this.skillGroups,
  });

  CharacterPageData copyWith({
    String? showcaseVideoId,
    String? name,
    String? portraitUrl,
    List<PillData>? pills,
    List<IconNameData>? materials,
    List<RankedData>? bestWeapons,
    List<RankedData>? bestArtifacts,
    List<String>? bestStatsLines,
    AscensionTableData? ascension,
    List<SkillGroupData>? skillGroups,
  }) {
    return CharacterPageData(
      showcaseVideoId: showcaseVideoId ?? this.showcaseVideoId,
      name: name ?? this.name,
      portraitUrl: portraitUrl ?? this.portraitUrl,
      pills: pills ?? this.pills,
      materials: materials ?? this.materials,
      bestWeapons: bestWeapons ?? this.bestWeapons,
      bestArtifacts: bestArtifacts ?? this.bestArtifacts,
      bestStatsLines: bestStatsLines ?? this.bestStatsLines,
      ascension: ascension ?? this.ascension,
      skillGroups: skillGroups ?? this.skillGroups,
    );
  }
}
