// Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of protobuf;

typedef void CheckFunc<E>(E x);

class FrozenPbList<E> extends PbListBase<E> {
  FrozenPbList._(List<E> wrappedList) : super._(wrappedList);

  factory FrozenPbList.from(PbList<E> other) =>
      FrozenPbList._(other._wrappedList);

  UnsupportedError _unsupported(String method) =>
      UnsupportedError("Cannot call $method on an unmodifiable list");

  void operator []=(int index, E value) => throw _unsupported("set");
  set length(int newLength) => throw _unsupported("set length");
  void setAll(int at, Iterable<E> iterable) => throw _unsupported("setAll");
  void add(E value) => throw _unsupported("add");
  void addAll(Iterable<E> iterable) => throw _unsupported("addAll");
  void insert(int index, E element) => throw _unsupported("insert");
  void insertAll(int at, Iterable<E> iterable) =>
      throw _unsupported("insertAll");
  bool remove(Object element) => throw _unsupported("remove");
  void removeWhere(bool test(E element)) => throw _unsupported("removeWhere");
  void retainWhere(bool test(E element)) => throw _unsupported("retainWhere");
  void sort([Comparator<E> compare]) => throw _unsupported("sort");
  void shuffle([math.Random random]) => throw _unsupported("shuffle");
  void clear() => throw _unsupported("clear");
  E removeAt(int index) => throw _unsupported("removeAt");
  E removeLast() => throw _unsupported("removeLast");
  void setRange(int start, int end, Iterable<E> iterable,
          [int skipCount = 0]) =>
      throw _unsupported("setRange");
  void removeRange(int start, int end) => throw _unsupported("removeRange");
  void replaceRange(int start, int end, Iterable<E> iterable) =>
      throw _unsupported("replaceRange");
  void fillRange(int start, int end, [E fillValue]) =>
      throw _unsupported("fillRange");
}

class PbList<E> extends PbListBase<E> {
  PbList({check = _checkNotNull}) : super._noList(check: check);

  PbList._(List<E> wrappedList) : super._(wrappedList);

  PbList.from(List from) : super._from(from);

  @Deprecated('Instead use the default constructor with a check function.'
      'This constructor will be removed in the next major version.')
  PbList.forFieldType(int fieldType)
      : super._noList(check: getCheckFunction(fieldType));

  /// Freezes the list by converting to [FrozenPbList].
  FrozenPbList<E> toFrozenPbList() => FrozenPbList<E>.from(this);

  /// Adds [value] at the end of the list, extending the length by one.
  /// Throws an [UnsupportedError] if the list is not extendable.
  void add(E value) {
    check(value);
    _wrappedList.add(value);
  }

  /// Appends all elements of the [collection] to the end of list.
  /// Extends the length of the list by the length of [collection].
  /// Throws an [UnsupportedError] if the list is not extendable.
  void addAll(Iterable<E> collection) {
    collection.forEach(check);
    _wrappedList.addAll(collection);
  }

  /// Returns an [Iterable] of the objects in this list in reverse order.
  Iterable<E> get reversed => _wrappedList.reversed;

  /// Sorts this list according to the order specified by the [compare]
  /// function.
  void sort([int compare(E a, E b)]) => _wrappedList.sort(compare);

  /// Shuffles the elements of this list randomly.
  void shuffle([math.Random random]) => _wrappedList.shuffle(random);

  /// Removes all objects from this list; the length of the list becomes zero.
  void clear() => _wrappedList.clear();

  /// Inserts a new element in the list.
  /// The element must be valid (and not nullable) for the PbList type.
  void insert(int index, E element) {
    check(element);
    _wrappedList.insert(index, element);
  }

  /// Inserts all elements of [iterable] at position [index] in the list.
  ///
  /// Elements in [iterable] must be valid and not nullable for the PbList type.
  void insertAll(int index, Iterable<E> iterable) {
    iterable.forEach(check);
    _wrappedList.insertAll(index, iterable);
  }

  /// Overwrites elements of `this` with elements of [iterable] starting at
  /// position [index] in the list.
  ///
  /// Elements in [iterable] must be valid and not nullable for the PbList type.
  void setAll(int index, Iterable<E> iterable) {
    iterable.forEach(check);
    _wrappedList.setAll(index, iterable);
  }

  /// Removes the first occurrence of [value] from this list.
  bool remove(Object value) => _wrappedList.remove(value);

  /// Removes the object at position [index] from this list.
  E removeAt(int index) => _wrappedList.removeAt(index);

  /// Pops and returns the last object in this list.
  E removeLast() => _wrappedList.removeLast();

  /// Removes all objects from this list that satisfy [test].
  void removeWhere(bool test(E element)) => _wrappedList.removeWhere(test);

  /// Removes all objects from this list that fail to satisfy [test].
  void retainWhere(bool test(E element)) => _wrappedList.retainWhere(test);

  /// Copies [:end - start:] elements of the [from] array, starting from
  /// [skipCount], into [:this:], starting at [start].
  /// Throws an [UnsupportedError] if the list is not extendable.
  void setRange(int start, int end, Iterable<E> from, [int skipCount = 0]) {
    // NOTE: In case `take()` returns less than `end - start` elements, the
    // _wrappedList will fail with a `StateError`.
    from.skip(skipCount).take(end - start).forEach(check);
    _wrappedList.setRange(start, end, from, skipCount);
  }

  /// Removes the objects in the range [start] inclusive to [end] exclusive.
  void removeRange(int start, int end) => _wrappedList.removeRange(start, end);

  /// Sets the objects in the range [start] inclusive to [end] exclusive to the
  /// given [fillValue].
  void fillRange(int start, int end, [E fillValue]) {
    check(fillValue);
    _wrappedList.fillRange(start, end, fillValue);
  }

  /// Removes the objects in the range [start] inclusive to [end] exclusive and
  /// inserts the contents of [replacement] in its place.
  void replaceRange(int start, int end, Iterable<E> replacement) {
    final values = replacement.toList();
    replacement.forEach(check);
    _wrappedList.replaceRange(start, end, values);
  }
}

abstract class PbListBase<E> extends ListBase<E> {
  final List<E> _wrappedList;
  final CheckFunc<E> check;

  PbListBase._(this._wrappedList, {this.check = _checkNotNull});

  PbListBase._noList({this.check = _checkNotNull}) : _wrappedList = <E>[] {
    assert(check != null);
  }

  PbListBase._from(List from)
      // TODO(sra): Should this be validated?
      : _wrappedList = List<E>.from(from),
        check = _checkNotNull;

  @override
  bool operator ==(other) =>
      (other is PbListBase) && _areListsEqual(other, this);

  @override
  int get hashCode => _HashUtils._hashObjects(_wrappedList);

  /// Returns an [Iterator] for the list.
  Iterator<E> get iterator => _wrappedList.iterator;

  /// Returns a new lazy [Iterable] with elements that are created by calling
  /// `f` on each element of this `PbListBase` in iteration order.
  Iterable<T> map<T>(T f(E e)) => _wrappedList.map<T>(f);

  /// Returns a new lazy [Iterable] with all elements that satisfy the predicate
  /// [test].
  Iterable<E> where(bool test(E element)) => _wrappedList.where(test);

  /// Expands each element of this [Iterable] into zero or more elements.
  Iterable<T> expand<T>(Iterable<T> f(E element)) => _wrappedList.expand(f);

  /// Returns true if the collection contains an element equal to [element].
  bool contains(Object element) => _wrappedList.contains(element);

  /// Applies the function [f] to each element of this list in iteration order.
  void forEach(void f(E element)) {
    _wrappedList.forEach(f);
  }

  /// Reduces a collection to a single value by iteratively combining elements
  /// of the collection using the provided function.
  E reduce(E combine(E value, E element)) => _wrappedList.reduce(combine);

  /// Reduces a collection to a single value by iteratively combining each
  /// element of the collection with an existing value.
  T fold<T>(T initialValue, T combine(T previousValue, E element)) =>
      _wrappedList.fold(initialValue, combine);

  /// Checks whether every element of this iterable satisfies [test].
  bool every(bool test(E element)) => _wrappedList.every(test);

  /// Converts each element to a [String] and concatenates the strings.
  String join([String separator = ""]) => _wrappedList.join(separator);

  /// Checks whether any element of this iterable satisfies [test].
  bool any(bool test(E element)) => _wrappedList.any(test);

  /// Creates a [List] containing the elements of this [Iterable].
  List<E> toList({bool growable = true}) =>
      _wrappedList.toList(growable: growable);

  /// Creates a [Set] containing the same elements as this iterable.
  Set<E> toSet() => _wrappedList.toSet();

  /// Returns `true` if there are no elements in this collection.
  bool get isEmpty => _wrappedList.isEmpty;

  /// Returns `true` if there is at least one element in this collection.
  bool get isNotEmpty => _wrappedList.isNotEmpty;

  /// Returns a lazy iterable of the [count] first elements of this iterable.
  Iterable<E> take(int count) => _wrappedList.take(count);

  /// Returns a lazy iterable of the leading elements satisfying [test].
  Iterable<E> takeWhile(bool test(E value)) => _wrappedList.takeWhile(test);

  /// Returns an [Iterable] that provides all but the first [count] elements.
  Iterable<E> skip(int count) => _wrappedList.skip(count);

  /// Returns an `Iterable` that skips leading elements while [test] is
  /// satisfied.
  Iterable<E> skipWhile(bool test(E value)) => _wrappedList.skipWhile(test);

  /// Returns the first element.
  E get first => _wrappedList.first;

  /// Returns the last element.
  E get last => _wrappedList.last;

  /// Checks that this iterable has only one element, and returns that element.
  E get single => _wrappedList.single;

  /// Returns the first element that satisfies the given predicate [test].
  E firstWhere(bool test(E element), {E orElse()}) =>
      _wrappedList.firstWhere(test, orElse: orElse);

  /// Returns the last element that satisfies the given predicate [test].
  E lastWhere(bool test(E element), {E orElse()}) =>
      _wrappedList.lastWhere(test, orElse: orElse);

  /// Returns the single element that satisfies [test].
  // TODO(jakobr): Implement once Dart 2 corelib changes have landed.
  //E singleWhere(bool test(E element), {E orElse()}) =>
  //    _wrappedList.singleWhere(test, orElse: orElse);

  /// Returns the [index]th element.
  E elementAt(int index) => _wrappedList.elementAt(index);

  /// Returns a string representation of (some of) the elements of `this`.
  String toString() => _wrappedList.toString();

  /// Returns the element at the given [index] in the list or throws an
  /// [IndexOutOfRangeException] if [index] is out of bounds.
  @override
  E operator [](int index) => _wrappedList[index];

  /// Returns the number of elements in this collection.
  int get length => _wrappedList.length;

  // TODO(jakobr): E instead of Object once dart-lang/sdk#31311 is fixed.
  /// Returns the first index of [element] in this list.
  int indexOf(Object element, [int start = 0]) =>
      _wrappedList.indexOf(element, start);

  // TODO(jakobr): E instead of Object once dart-lang/sdk#31311 is fixed.
  /// Returns the last index of [element] in this list.
  int lastIndexOf(Object element, [int start]) =>
      _wrappedList.lastIndexOf(element, start);

  /// Returns a new list containing the objects from [start] inclusive to [end]
  /// exclusive.
  List<E> sublist(int start, [int end]) => _wrappedList.sublist(start, end);

  /// Returns an [Iterable] that iterates over the objects in the range [start]
  /// inclusive to [end] exclusive.
  Iterable<E> getRange(int start, int end) => _wrappedList.getRange(start, end);

  /// Returns an unmodifiable [Map] view of `this`.
  Map<int, E> asMap() => _wrappedList.asMap();

  /// Sets the entry at the given [index] in the list to [value].
  /// Throws an [IndexOutOfRangeException] if [index] is out of bounds.
  @override
  void operator []=(int index, E value) {
    check(value);
    _wrappedList[index] = value;
  }

  /// Unsupported -- violated non-null constraint imposed by protobufs.
  ///
  /// Changes the length of the list. If [newLength] is greater than the current
  /// [length], entries are initialized to [:null:]. Throws an
  /// [UnsupportedError] if the list is not extendable.
  set length(int newLength) {
    if (newLength > length) {
      throw UnsupportedError('Extending protobuf lists is not supported');
    }
    _wrappedList.length = newLength;
  }
}
