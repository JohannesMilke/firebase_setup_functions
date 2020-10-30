// Copyright (c) 2017, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of code_builder.src.specs.expression;

Expression toClosure(Method method) {
  final withoutTypes = method.rebuild((b) {
    b.returns = null;
    b.types.clear();
  });
  return ClosureExpression._(withoutTypes);
}

class ClosureExpression extends Expression {
  final Method method;

  const ClosureExpression._(this.method);

  @override
  R accept<R>(ExpressionVisitor<R> visitor, [R context]) =>
      visitor.visitClosureExpression(this, context);
}
