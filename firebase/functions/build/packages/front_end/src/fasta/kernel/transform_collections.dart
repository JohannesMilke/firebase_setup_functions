// Copyright (c) 2019, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

library fasta.transform_collections;

import 'dart:core' hide MapEntry;

import 'package:kernel/ast.dart'
    show
        Arguments,
        AsExpression,
        Block,
        BlockExpression,
        Class,
        ConditionalExpression,
        DartType,
        DynamicType,
        Expression,
        ExpressionStatement,
        Field,
        ForInStatement,
        ForStatement,
        IfStatement,
        InterfaceType,
        Let,
        ListConcatenation,
        ListLiteral,
        MapConcatenation,
        MapEntry,
        MapLiteral,
        MethodInvocation,
        Name,
        Not,
        NullLiteral,
        Procedure,
        PropertyGet,
        SetConcatenation,
        SetLiteral,
        Statement,
        StaticInvocation,
        transformList,
        TreeNode,
        VariableDeclaration,
        VariableGet;

import 'package:kernel/core_types.dart' show CoreTypes;

import 'package:kernel/type_environment.dart'
    show SubtypeCheckMode, TypeEnvironment;

import 'package:kernel/visitor.dart' show Transformer;

import 'collections.dart'
    show
        ControlFlowElement,
        ControlFlowMapEntry,
        ForElement,
        ForInElement,
        ForInMapEntry,
        ForMapEntry,
        IfElement,
        IfMapEntry,
        SpreadElement,
        SpreadMapEntry;

import '../problems.dart' show getFileUri, unhandled;

import '../source/source_loader.dart' show SourceLoader;

import 'redirecting_factory_body.dart' show RedirectingFactoryBody;

class CollectionTransformer extends Transformer {
  final CoreTypes coreTypes;
  final TypeEnvironment typeEnvironment;
  final Procedure listAdd;
  final Procedure setFactory;
  final Procedure setAdd;
  final Procedure objectEquals;
  final Procedure mapEntries;
  final Procedure mapPut;
  final Class mapEntryClass;
  final Field mapEntryKey;
  final Field mapEntryValue;

  static Procedure _findSetFactory(CoreTypes coreTypes) {
    Procedure factory = coreTypes.index.getMember('dart:core', 'Set', '');
    RedirectingFactoryBody body = factory?.function?.body;
    return body?.target;
  }

  CollectionTransformer(SourceLoader loader)
      : coreTypes = loader.coreTypes,
        typeEnvironment = loader.typeInferenceEngine.typeSchemaEnvironment,
        listAdd = loader.coreTypes.index.getMember('dart:core', 'List', 'add'),
        setFactory = _findSetFactory(loader.coreTypes),
        setAdd = loader.coreTypes.index.getMember('dart:core', 'Set', 'add'),
        objectEquals =
            loader.coreTypes.index.getMember('dart:core', 'Object', '=='),
        mapEntries =
            loader.coreTypes.index.getMember('dart:core', 'Map', 'get:entries'),
        mapPut = loader.coreTypes.index.getMember('dart:core', 'Map', '[]='),
        mapEntryClass =
            loader.coreTypes.index.getClass('dart:core', 'MapEntry'),
        mapEntryKey =
            loader.coreTypes.index.getMember('dart:core', 'MapEntry', 'key'),
        mapEntryValue =
            loader.coreTypes.index.getMember('dart:core', 'MapEntry', 'value');

  TreeNode _translateListOrSet(
      Expression node, DartType elementType, List<Expression> elements,
      {bool isSet: false}) {
    // Translate elements in place up to the first non-expression, if any.
    int i = 0;
    for (; i < elements.length; ++i) {
      if (elements[i] is ControlFlowElement) break;
      elements[i] = elements[i].accept<TreeNode>(this)..parent = node;
    }

    // If there were only expressions, we are done.
    if (i == elements.length) return node;

    // Build a block expression and create an empty list or set.
    VariableDeclaration result;
    if (isSet) {
      // TODO(kmillikin): When all the back ends handle set literals we can use
      // one here.
      result = new VariableDeclaration.forValue(
          new StaticInvocation(
              setFactory, new Arguments([], types: [elementType])),
          type: new InterfaceType(coreTypes.setClass, [elementType]),
          isFinal: true);
    } else {
      result = new VariableDeclaration.forValue(
          new ListLiteral([], typeArgument: elementType),
          type: new InterfaceType(coreTypes.listClass, [elementType]),
          isFinal: true);
    }
    List<Statement> body = [result];
    // Add the elements up to the first non-expression.
    for (int j = 0; j < i; ++j) {
      _addExpressionElement(elements[j], isSet, result, body);
    }
    // Translate the elements starting with the first non-expression.
    for (; i < elements.length; ++i) {
      _translateElement(elements[i], elementType, isSet, result, body);
    }

    return new BlockExpression(new Block(body), new VariableGet(result));
  }

  void _translateElement(Expression element, DartType elementType, bool isSet,
      VariableDeclaration result, List<Statement> body) {
    if (element is SpreadElement) {
      _translateSpreadElement(element, elementType, isSet, result, body);
    } else if (element is IfElement) {
      _translateIfElement(element, elementType, isSet, result, body);
    } else if (element is ForElement) {
      _translateForElement(element, elementType, isSet, result, body);
    } else if (element is ForInElement) {
      _translateForInElement(element, elementType, isSet, result, body);
    } else {
      _addExpressionElement(
          element.accept<TreeNode>(this), isSet, result, body);
    }
  }

  void _addExpressionElement(Expression element, bool isSet,
      VariableDeclaration result, List<Statement> body) {
    body.add(new ExpressionStatement(new MethodInvocation(
        new VariableGet(result),
        new Name('add'),
        new Arguments([element]),
        isSet ? setAdd : listAdd)));
  }

  void _translateIfElement(IfElement element, DartType elementType, bool isSet,
      VariableDeclaration result, List<Statement> body) {
    List<Statement> thenStatements = [];
    _translateElement(element.then, elementType, isSet, result, thenStatements);
    List<Statement> elseStatements;
    if (element.otherwise != null) {
      _translateElement(element.otherwise, elementType, isSet, result,
          elseStatements = <Statement>[]);
    }
    Statement thenBody = thenStatements.length == 1
        ? thenStatements.first
        : new Block(thenStatements);
    Statement elseBody;
    if (elseStatements != null && elseStatements.isNotEmpty) {
      elseBody = elseStatements.length == 1
          ? elseStatements.first
          : new Block(elseStatements);
    }
    body.add(new IfStatement(
        element.condition.accept<TreeNode>(this), thenBody, elseBody)
      ..fileOffset = element.fileOffset);
  }

  void _translateForElement(ForElement element, DartType elementType,
      bool isSet, VariableDeclaration result, List<Statement> body) {
    List<Statement> statements = <Statement>[];
    _translateElement(element.body, elementType, isSet, result, statements);
    Statement loopBody =
        statements.length == 1 ? statements.first : new Block(statements);
    ForStatement loop = new ForStatement(element.variables,
        element.condition?.accept<TreeNode>(this), element.updates, loopBody)
      ..fileOffset = element.fileOffset;
    transformList(loop.variables, this, loop);
    transformList(loop.updates, this, loop);
    body.add(loop);
  }

  void _translateForInElement(ForInElement element, DartType elementType,
      bool isSet, VariableDeclaration result, List<Statement> body) {
    List<Statement> statements;
    Statement prologue = element.prologue;
    if (prologue == null) {
      statements = <Statement>[];
    } else {
      prologue = prologue.accept<TreeNode>(this);
      statements =
          prologue is Block ? prologue.statements : <Statement>[prologue];
    }
    _translateElement(element.body, elementType, isSet, result, statements);
    Statement loopBody =
        statements.length == 1 ? statements.first : new Block(statements);
    if (element.problem != null) {
      body.add(new ExpressionStatement(element.problem.accept<TreeNode>(this)));
    }
    body.add(new ForInStatement(
        element.variable, element.iterable.accept<TreeNode>(this), loopBody,
        isAsync: element.isAsync)
      ..fileOffset = element.fileOffset);
  }

  void _translateSpreadElement(SpreadElement element, DartType elementType,
      bool isSet, VariableDeclaration result, List<Statement> body) {
    Expression value = element.expression.accept<TreeNode>(this);
    // Null-aware spreads require testing the subexpression's value.
    VariableDeclaration temp;
    if (element.isNullAware) {
      temp = new VariableDeclaration.forValue(value,
          type: const DynamicType(), isFinal: true);
      body.add(temp);
      value = new VariableGet(temp);
    }

    VariableDeclaration elt;
    Statement loopBody;
    if (element.elementType == null ||
        !typeEnvironment.isSubtypeOf(element.elementType, elementType,
            SubtypeCheckMode.ignoringNullabilities)) {
      elt = new VariableDeclaration(null,
          type: const DynamicType(), isFinal: true);
      VariableDeclaration castedVar = new VariableDeclaration.forValue(
          new AsExpression(new VariableGet(elt), elementType)
            ..isTypeError = true
            ..fileOffset = element.expression.fileOffset,
          type: elementType);
      loopBody = new Block(<Statement>[
        castedVar,
        new ExpressionStatement(new MethodInvocation(
            new VariableGet(result),
            new Name('add'),
            new Arguments([new VariableGet(castedVar)]),
            isSet ? setAdd : listAdd))
      ]);
    } else {
      elt = new VariableDeclaration(null, type: elementType, isFinal: true);
      loopBody = new ExpressionStatement(new MethodInvocation(
          new VariableGet(result),
          new Name('add'),
          new Arguments([new VariableGet(elt)]),
          isSet ? setAdd : listAdd));
    }
    Statement statement = new ForInStatement(elt, value, loopBody);

    if (element.isNullAware) {
      statement = new IfStatement(
          new Not(new MethodInvocation(new VariableGet(temp), new Name('=='),
              new Arguments([new NullLiteral()]), objectEquals)),
          statement,
          null);
    }
    body.add(statement);
  }

  @override
  TreeNode visitListLiteral(ListLiteral node) {
    if (node.isConst) {
      return _translateConstListOrSet(node, node.typeArgument, node.expressions,
          isSet: false);
    }

    return _translateListOrSet(node, node.typeArgument, node.expressions,
        isSet: false);
  }

  @override
  TreeNode visitSetLiteral(SetLiteral node) {
    if (node.isConst) {
      return _translateConstListOrSet(node, node.typeArgument, node.expressions,
          isSet: true);
    }

    return _translateListOrSet(node, node.typeArgument, node.expressions,
        isSet: true);
  }

  @override
  TreeNode visitMapLiteral(MapLiteral node) {
    if (node.isConst) {
      return _translateConstMap(node);
    }

    // Translate entries in place up to the first control-flow entry, if any.
    int i = 0;
    for (; i < node.entries.length; ++i) {
      if (node.entries[i] is ControlFlowMapEntry) break;
      node.entries[i] = node.entries[i].accept<TreeNode>(this)..parent = node;
    }

    // If there were no control-flow entries we are done.
    if (i == node.entries.length) return node;

    // Build a block expression and create an empty map.
    VariableDeclaration result = new VariableDeclaration.forValue(
        new MapLiteral([], keyType: node.keyType, valueType: node.valueType),
        type: new InterfaceType(
            coreTypes.mapClass, [node.keyType, node.valueType]),
        isFinal: true);
    List<Statement> body = [result];
    // Add all the entries up to the first control-flow entry.
    for (int j = 0; j < i; ++j) {
      _addNormalEntry(node.entries[j], result, body);
    }
    for (; i < node.entries.length; ++i) {
      _translateEntry(
          node.entries[i], node.keyType, node.valueType, result, body);
    }

    return new BlockExpression(new Block(body), new VariableGet(result));
  }

  void _translateEntry(MapEntry entry, DartType keyType, DartType valueType,
      VariableDeclaration result, List<Statement> body) {
    if (entry is SpreadMapEntry) {
      _translateSpreadEntry(entry, keyType, valueType, result, body);
    } else if (entry is IfMapEntry) {
      _translateIfEntry(entry, keyType, valueType, result, body);
    } else if (entry is ForMapEntry) {
      _translateForEntry(entry, keyType, valueType, result, body);
    } else if (entry is ForInMapEntry) {
      _translateForInEntry(entry, keyType, valueType, result, body);
    } else {
      _addNormalEntry(entry.accept<TreeNode>(this), result, body);
    }
  }

  void _addNormalEntry(
      MapEntry entry, VariableDeclaration result, List<Statement> body) {
    body.add(new ExpressionStatement(new MethodInvocation(
        new VariableGet(result),
        new Name('[]='),
        new Arguments([entry.key, entry.value]),
        mapPut)));
  }

  void _translateIfEntry(IfMapEntry entry, DartType keyType, DartType valueType,
      VariableDeclaration result, List<Statement> body) {
    List<Statement> thenBody = [];
    _translateEntry(entry.then, keyType, valueType, result, thenBody);
    List<Statement> elseBody;
    if (entry.otherwise != null) {
      _translateEntry(entry.otherwise, keyType, valueType, result,
          elseBody = <Statement>[]);
    }
    Statement thenStatement =
        thenBody.length == 1 ? thenBody.first : new Block(thenBody);
    Statement elseStatement;
    if (elseBody != null && elseBody.isNotEmpty) {
      elseStatement =
          elseBody.length == 1 ? elseBody.first : new Block(elseBody);
    }
    body.add(new IfStatement(
        entry.condition.accept<TreeNode>(this), thenStatement, elseStatement));
  }

  void _translateForEntry(ForMapEntry entry, DartType keyType,
      DartType valueType, VariableDeclaration result, List<Statement> body) {
    List<Statement> statements = <Statement>[];
    _translateEntry(entry.body, keyType, valueType, result, statements);
    Statement loopBody =
        statements.length == 1 ? statements.first : new Block(statements);
    ForStatement loop = new ForStatement(entry.variables,
        entry.condition?.accept<TreeNode>(this), entry.updates, loopBody)
      ..fileOffset = entry.fileOffset;
    transformList(loop.variables, this, loop);
    transformList(loop.updates, this, loop);
    body.add(loop);
  }

  void _translateForInEntry(ForInMapEntry entry, DartType keyType,
      DartType valueType, VariableDeclaration result, List<Statement> body) {
    List<Statement> statements;
    Statement prologue = entry.prologue;
    if (prologue == null) {
      statements = <Statement>[];
    } else {
      prologue = prologue.accept<TreeNode>(this);
      statements =
          prologue is Block ? prologue.statements : <Statement>[prologue];
    }
    _translateEntry(entry.body, keyType, valueType, result, statements);
    Statement loopBody =
        statements.length == 1 ? statements.first : new Block(statements);
    if (entry.problem != null) {
      body.add(new ExpressionStatement(entry.problem.accept<TreeNode>(this)));
    }
    body.add(new ForInStatement(
        entry.variable, entry.iterable.accept<TreeNode>(this), loopBody,
        isAsync: entry.isAsync)
      ..fileOffset = entry.fileOffset);
  }

  void _translateSpreadEntry(SpreadMapEntry entry, DartType keyType,
      DartType valueType, VariableDeclaration result, List<Statement> body) {
    Expression value = entry.expression.accept<TreeNode>(this);
    // Null-aware spreads require testing the subexpression's value.
    VariableDeclaration temp;
    if (entry.isNullAware) {
      temp = new VariableDeclaration.forValue(value,
          type: coreTypes.mapLegacyRawType);
      body.add(temp);
      value = new VariableGet(temp);
    }

    DartType entryType =
        new InterfaceType(mapEntryClass, <DartType>[keyType, valueType]);
    VariableDeclaration elt;
    Statement loopBody;
    if (entry.entryType == null ||
        !typeEnvironment.isSubtypeOf(entry.entryType, entryType,
            SubtypeCheckMode.ignoringNullabilities)) {
      elt = new VariableDeclaration(null,
          type: new InterfaceType(mapEntryClass,
              <DartType>[const DynamicType(), const DynamicType()]),
          isFinal: true);
      VariableDeclaration keyVar = new VariableDeclaration.forValue(
          new AsExpression(
              new PropertyGet(
                  new VariableGet(elt), new Name('key'), mapEntryKey),
              keyType)
            ..isTypeError = true
            ..fileOffset = entry.expression.fileOffset,
          type: keyType);
      VariableDeclaration valueVar = new VariableDeclaration.forValue(
          new AsExpression(
              new PropertyGet(
                  new VariableGet(elt), new Name('value'), mapEntryValue),
              valueType)
            ..isTypeError = true
            ..fileOffset = entry.expression.fileOffset,
          type: valueType);
      loopBody = new Block(<Statement>[
        keyVar,
        valueVar,
        new ExpressionStatement(new MethodInvocation(
            new VariableGet(result),
            new Name('[]='),
            new Arguments([new VariableGet(keyVar), new VariableGet(valueVar)]),
            mapPut))
      ]);
    } else {
      elt = new VariableDeclaration(null, type: entryType, isFinal: true);
      loopBody = new ExpressionStatement(new MethodInvocation(
          new VariableGet(result),
          new Name('[]='),
          new Arguments([
            new PropertyGet(new VariableGet(elt), new Name('key'), mapEntryKey),
            new PropertyGet(
                new VariableGet(elt), new Name('value'), mapEntryValue)
          ]),
          mapPut));
    }
    Statement statement = new ForInStatement(
        elt, new PropertyGet(value, new Name('entries'), mapEntries), loopBody);

    if (entry.isNullAware) {
      statement = new IfStatement(
          new Not(new MethodInvocation(new VariableGet(temp), new Name('=='),
              new Arguments([new NullLiteral()]), objectEquals)),
          statement,
          null);
    }
    body.add(statement);
  }

  TreeNode _translateConstListOrSet(
      Expression node, DartType elementType, List<Expression> elements,
      {bool isSet: false}) {
    // Translate elements in place up to the first non-expression, if any.
    int i = 0;
    for (; i < elements.length; ++i) {
      if (elements[i] is ControlFlowElement) break;
      elements[i] = elements[i].accept<TreeNode>(this)..parent = node;
    }

    // If there were only expressions, we are done.
    if (i == elements.length) return node;

    Expression makeLiteral(List<Expression> expressions) {
      return isSet
          ? new SetLiteral(expressions,
              typeArgument: elementType, isConst: true)
          : new ListLiteral(expressions,
              typeArgument: elementType, isConst: true);
    }

    // Build a concatenation node.
    List<Expression> parts = [];
    List<Expression> currentPart = i > 0 ? elements.sublist(0, i) : null;

    for (; i < elements.length; ++i) {
      Expression element = elements[i];
      if (element is SpreadElement) {
        if (currentPart != null) {
          parts.add(makeLiteral(currentPart));
          currentPart = null;
        }
        Expression spreadExpression = element.expression.accept<TreeNode>(this);
        if (element.isNullAware) {
          VariableDeclaration temp =
              new VariableDeclaration(null, initializer: spreadExpression);
          parts.add(new Let(
              temp,
              new ConditionalExpression(
                  new MethodInvocation(new VariableGet(temp), new Name('=='),
                      new Arguments([new NullLiteral()])),
                  makeLiteral([]),
                  new VariableGet(temp),
                  const DynamicType())));
        } else {
          parts.add(spreadExpression);
        }
      } else if (element is IfElement) {
        if (currentPart != null) {
          parts.add(makeLiteral(currentPart));
          currentPart = null;
        }
        Expression condition = element.condition.accept<TreeNode>(this);
        Expression then = makeLiteral([element.then]).accept<TreeNode>(this);
        Expression otherwise = element.otherwise != null
            ? makeLiteral([element.otherwise]).accept<TreeNode>(this)
            : makeLiteral([]);
        parts.add(new ConditionalExpression(
            condition, then, otherwise, const DynamicType()));
      } else if (element is ForElement || element is ForInElement) {
        // Rejected earlier.
        unhandled("${element.runtimeType}", "_translateConstListOrSet",
            element.fileOffset, getFileUri(element));
      } else {
        currentPart ??= <Expression>[];
        currentPart.add(element.accept<TreeNode>(this));
      }
    }
    if (currentPart != null) {
      parts.add(makeLiteral(currentPart));
    }
    return isSet
        ? new SetConcatenation(parts, typeArgument: elementType)
        : new ListConcatenation(parts, typeArgument: elementType);
  }

  TreeNode _translateConstMap(MapLiteral node) {
    // Translate entries in place up to the first control-flow entry, if any.
    int i = 0;
    for (; i < node.entries.length; ++i) {
      if (node.entries[i] is ControlFlowMapEntry) break;
      node.entries[i] = node.entries[i].accept<TreeNode>(this)..parent = node;
    }

    // If there were no control-flow entries we are done.
    if (i == node.entries.length) return node;

    MapLiteral makeLiteral(List<MapEntry> entries) {
      return new MapLiteral(entries,
          keyType: node.keyType, valueType: node.valueType, isConst: true);
    }

    // Build a concatenation node.
    List<Expression> parts = [];
    List<MapEntry> currentPart = i > 0 ? node.entries.sublist(0, i) : null;

    for (; i < node.entries.length; ++i) {
      MapEntry entry = node.entries[i];
      if (entry is SpreadMapEntry) {
        if (currentPart != null) {
          parts.add(makeLiteral(currentPart));
          currentPart = null;
        }
        Expression spreadExpression = entry.expression.accept<TreeNode>(this);
        if (entry.isNullAware) {
          VariableDeclaration temp =
              new VariableDeclaration(null, initializer: spreadExpression);
          parts.add(new Let(
              temp,
              new ConditionalExpression(
                  new MethodInvocation(new VariableGet(temp), new Name('=='),
                      new Arguments([new NullLiteral()])),
                  makeLiteral([]),
                  new VariableGet(temp),
                  const DynamicType())));
        } else {
          parts.add(spreadExpression);
        }
      } else if (entry is IfMapEntry) {
        if (currentPart != null) {
          parts.add(makeLiteral(currentPart));
          currentPart = null;
        }
        Expression condition = entry.condition.accept<TreeNode>(this);
        Expression then = makeLiteral([entry.then]).accept<TreeNode>(this);
        Expression otherwise = entry.otherwise != null
            ? makeLiteral([entry.otherwise]).accept<TreeNode>(this)
            : makeLiteral([]);
        parts.add(new ConditionalExpression(
            condition, then, otherwise, const DynamicType()));
      } else if (entry is ForMapEntry || entry is ForInMapEntry) {
        // Rejected earlier.
        unhandled("${entry.runtimeType}", "_translateConstMap",
            entry.fileOffset, getFileUri(entry));
      } else {
        currentPart ??= <MapEntry>[];
        currentPart.add(entry.accept<TreeNode>(this));
      }
    }
    if (currentPart != null) {
      parts.add(makeLiteral(currentPart));
    }
    return new MapConcatenation(parts,
        keyType: node.keyType, valueType: node.valueType);
  }
}
