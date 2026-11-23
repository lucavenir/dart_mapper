import 'package:built_collection/built_collection.dart' as built;
import 'package:dart_mapper/dart_mapper.dart';
import 'package:source_gen_test/annotations.dart';

class CollSource {
  final List<int> numbers;
  final Set<String> tags;

  CollSource({required this.numbers, required this.tags});
}

class CollTarget {
  final List<int> numbers;
  final Set<String> tags;

  CollTarget({required this.numbers, required this.tags});
}

@ShouldGenerate(
  r'''class CollMapperImpl extends CollMapper {
  CollMapperImpl();

  @override
  CollTarget toTarget(CollSource source) {
    return CollTarget(
      numbers: source.numbers.map((item) => item).toList(growable: true),
      tags: source.tags.map((item) => item).toSet(),
    );
  }
}''',
  contains: true,
)
@Mapper()
abstract class CollMapper {
  CollTarget toTarget(CollSource source);
}

class CollectionCoercionSource {
  final List<int> numbers;
  final Set<String> tags;

  CollectionCoercionSource({
    required this.numbers,
    required this.tags,
  });
}

class CollectionCoercionTarget {
  final Set<int> numbers;
  final List<String> tags;

  CollectionCoercionTarget({
    required this.numbers,
    required this.tags,
  });
}

@ShouldGenerate(
  r'''class CollectionCoercionMapperImpl extends CollectionCoercionMapper {
  CollectionCoercionMapperImpl();

  @override
  CollectionCoercionTarget toTarget(CollectionCoercionSource source) {
    return CollectionCoercionTarget(
      numbers: source.numbers.map((item) => item).toSet(),
      tags: source.tags.map((item) => item).toList(growable: true),
    );
  }
}''',
  contains: true,
)
@Mapper()
abstract class CollectionCoercionMapper {
  CollectionCoercionTarget toTarget(CollectionCoercionSource source);
}

class Item {
  final String name;

  Item({required this.name});
}

class ItemDto {
  final String name;

  ItemDto({required this.name});
}

@ShouldGenerate(
  r'''List<ItemDto> toDtos<T extends Item>(List<T> items) {
    return items.map<ItemDto>(this.toDto).toList(growable: true);
  }''',
  contains: true,
)
@ShouldGenerate(
  r'''List<ItemDto> toDtosOrThrow(List<Item>? items) {
    if (items == null) throw ArgumentError.notNull('items');
    return items.map<ItemDto>(this.toDto).toList(growable: true);
  }''',
  contains: true,
)
@ShouldGenerate(
  r'''List<Map<String, dynamic>> toMaps(List<ItemDto> toMap) {
    return toMap.map<Map<String, dynamic>>(this.toMap).toList(growable: true);
  }''',
  contains: true,
)
@ShouldGenerate(
  r'''Set<ItemDto>? fromMaps({required Iterable<Map<String, Object?>>? maps}) {
    if (maps == null) return null;
    return maps.map<ItemDto>(this.fromMap).toSet();
  }''',
  contains: true,
)
@Mapper()
abstract class ItemCollectionMapper {
  List<ItemDto> toDtos<T extends Item>(List<T> items);
  List<ItemDto> toDtosOrThrow(List<Item>? items);
  List<Map<String, dynamic>> toMaps(List<ItemDto> toMap);
  Set<ItemDto>? fromMaps({required Iterable<Map<String, Object?>>? maps});
  ItemDto toDto(Item item);
  static ItemDto staticToDto(Item item) => ItemDto(name: item.name);
  Map<String, dynamic> toMap(ItemDto item);
  ItemDto fromMap(Map<String, Object?> map);
}

class NullableItemMapper {
  ItemDto? convert(Item? item) =>
      item == null ? null : ItemDto(name: item.name);

  static ItemDto? staticConvert(Item? item) =>
      item == null ? null : ItemDto(name: item.name);
}

@ShouldGenerate(
  r'''Iterable<ItemDto?> toIterable([List<Item?> items = const []]) {
    return items.map<ItemDto?>(this.nullableItemMapper.convert);
  }''',
  contains: true,
)
@ShouldGenerate(
  r'''return built.BuiltSet<ItemDto?>(
      items.map<ItemDto?>(this.nullableItemMapper.convert),
    );''',
  contains: true,
)
@Mapper(uses: {NullableItemMapper})
abstract class NullableItemCollectionMapper {
  Iterable<ItemDto?> toIterable([List<Item?> items = const []]);
  built.BuiltSet<ItemDto?> toBuiltSet(built.BuiltList<Item?> items);
}

@ShouldThrow(
  "No mapper method found for elements of 'toDtos' with source (Item? items element) returning ItemDto.\n"
  "Rejected candidates:\n"
  "  - MissingElementMapper.toDto(Item item): argument 1 (`items element`) may be null (Item?) but parameter 1 is Item\n"
  "Fix: Add a mapper method (in the mapper or in a mapper listed in uses) taking these parameters in this order and returning a value assignable to the target.",
  element: 'toDtos',
)
@Mapper()
abstract class MissingElementMapper {
  List<ItemDto> toDtos(List<Item?> items);
  ItemDto toDto(Item item);
}

@ShouldThrow(
  "Ambiguous mapper method for elements of 'toDtos': multiple methods match "
  "(AmbiguousElementMapper.first(Item item), AmbiguousElementMapper.second(Item item)).\n"
  "Fix: Make sure only one element mapping method matches.",
  element: 'toDtos',
)
@Mapper()
abstract class AmbiguousElementMapper {
  List<ItemDto> toDtos(List<Item> items);
  ItemDto first(Item item);
  ItemDto second(Item item);
}
