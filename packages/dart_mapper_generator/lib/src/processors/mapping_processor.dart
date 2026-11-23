/*
 * Copyright (c) 2026 MyLittleSuite
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

import 'package:analyzer/dart/element/type.dart';
import 'package:code_builder/code_builder.dart';
import 'package:dart_mapper_generator/src/extensions/dart_type.dart';
import 'package:dart_mapper_generator/src/extensions/expression.dart';
import 'package:dart_mapper_generator/src/models/mapper/mapping/mapping_parameter.dart';
import 'package:dart_mapper_generator/src/models/mapper/mapping/method/bases/bindable_mapping_method.dart';
import 'package:dart_mapper_generator/src/models/mapper/mapping/method/collection_mapping_method.dart';
import 'package:dart_mapper_generator/src/models/mapper/mapping/method/subclass_mapping_method.dart';
import 'package:dart_mapper_generator/src/models/mapping_behavior.dart';
import 'package:dart_mapper_generator/src/processors/component_processor.dart';
import 'package:dart_mapper_generator/src/processors/mapping_code/subclass_mapping_code_processor.dart';
import 'package:dart_mapper_generator/src/strategies/strategy_dispatcher.dart';

class MappingProcessor extends ComponentProcessor<Method> {
  final StrategyDispatcher<MappingBehavior, ComponentProcessor<Code>>
      methodCodeDispatcher;
  final SubclassMappingCodeProcessor subclassMappingCodeProcessor;

  const MappingProcessor({
    required this.methodCodeDispatcher,
    this.subclassMappingCodeProcessor = const SubclassMappingCodeProcessor(),
  });

  @override
  Method process(ProcessorContext context) {
    if (context is! ProcessorMethodContext) {
      throw ArgumentError(
        'Invalid context type. Expected ProcessorMethodContext.',
      );
    }

    final method = context.currentMethod;
    if (method is CollectionMappingMethod) {
      return _processCollection(context, method);
    }

    // Nullable parameters are optional, after the required ones. When a
    // nullable one precedes a required one, that would reorder the parameters
    // and break the override: all stay required, in their declared order.
    final lastRequired = method.parameters.lastIndexWhere((p) => !p.isNullable);
    final firstNullable = method.parameters.indexWhere((p) => p.isNullable);
    final reorders = firstNullable >= 0 && firstNullable < lastRequired;
    final requiredParameters = reorders
        ? method.parameters
        : method.parameters.where((p) => !p.isNullable);
    final optionalParameters = reorders
        ? <MappingParameter>[]
        : method.parameters.where((p) => p.isNullable);

    return Method(
      (builder) {
        if (method.isOverride) {
          builder.annotations.add(refer('override'));
        }

        builder
          ..name = method.name
          ..requiredParameters.addAll(
            _processParameters(context, requiredParameters),
          )
          ..optionalParameters.addAll(
            _processParameters(context, optionalParameters),
          )
          ..returns = _processReturns(context, method)
          ..body = method is SubclassMappingMethod
              ? subclassMappingCodeProcessor.process(context)
              : methodCodeDispatcher.get(method.behavior).process(context);
      },
    );
  }

  Method _processCollection(
    ProcessorMethodContext context,
    CollectionMappingMethod method,
  ) {
    final source = method.source;
    final sourceName = source.name!;
    final target = method.targetType;
    final returnType = context.resolveTypeDeep(target);
    final constructorType = refer(
      method.optionalReturn
          ? returnType.substring(0, returnType.length - 1)
          : returnType,
    );
    final parameter = Parameter((builder) {
      builder
        ..name = sourceName
        ..type = refer(context.resolveTypeDeep(source.type))
        ..named = source.isNamed
        ..required = source.isRequiredNamed;
      if (source.defaultValueCode case final code?) {
        builder.defaultTo = Code(code);
      }
    });

    final mapped = refer(sourceName).property('map').call(
      [refer('this').property(method.elementMapper.name)],
      {},
      [refer(context.resolveTypeDeep(method.targetItemType))],
    );
    final result = switch (target) {
      DartType(isDartCoreList: true) => mapped.propertyToList(),
      DartType(isDartCoreSet: true) => mapped.propertyToSet(),
      DartType(isBuiltList: true) ||
      DartType(isBuiltSet: true) ||
      DartType(isFicIList: true) ||
      DartType(isFicISet: true) =>
        constructorType.newInstance([mapped]),
      DartType(isFicListSet: true) => constructorType.newInstanceNamed(
          'of',
          [mapped],
        ),
      _ => mapped,
    };

    return Method((builder) {
      builder
        ..annotations.add(refer('override'))
        ..name = method.name
        ..types.addAll(method.typeParameters.map(
          (parameter) => TypeReference((type) {
            type.symbol = parameter.name;
            if (parameter.bound case final bound?) {
              type.bound = refer(context.resolveTypeDeep(bound));
            }
          }),
        ))
        ..returns = refer(returnType)
        ..body = Block.of([
          if (source.type.isNullable)
            method.optionalReturn
                ? Code('if ($sourceName == null) return null;')
                : Code(
                    "if ($sourceName == null) throw ArgumentError.notNull('$sourceName');",
                  ),
          result.returned.statement,
        ]);
      if (source.isRequiredPositional) {
        builder.requiredParameters.add(parameter);
      } else {
        builder.optionalParameters.add(parameter);
      }
    });
  }

  Iterable<Parameter> _processParameters(
    ProcessorMethodContext context,
    Iterable<MappingParameter> parameters,
  ) =>
      parameters.map(
        (p) => Parameter(
          (b) => b
            ..name = p.field.name
            ..type = refer(_resolveParameterType(context, p)),
        ),
      );

  /// Map parameters keep the nullability of their value type
  /// (`Map<String, String?>`), which the plain display string strips.
  String _resolveParameterType(
    ProcessorMethodContext context,
    MappingParameter parameter,
  ) {
    final type = parameter.field.type;
    if (!type.isMapLikeSource) {
      return context.resolveType(
        type,
        withNullability: parameter.field.nullable,
      );
    }

    final display = context.resolveTypeDeep(type);

    return parameter.field.nullable && !display.endsWith('?')
        ? '$display?'
        : display;
  }

  Reference _processReturns(
    ProcessorMethodContext context,
    BindableMappingMethod method,
  ) {
    final returnType = method.returnType;
    if (returnType == null) {
      return refer('void');
    }

    if (!method.isOverride &&
        (method.behavior == MappingBehavior.built ||
            (method.behavior == MappingBehavior.fromMap &&
                returnType.isBuiltValue))) {
      return refer(returnType.builtBuilderClass);
    }

    return refer(context.resolveType(
      returnType,
      withNullability: method.optionalReturn,
    ));
  }
}
