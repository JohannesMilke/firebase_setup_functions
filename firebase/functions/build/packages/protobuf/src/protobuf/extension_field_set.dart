// Copyright (c) 2015, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

part of protobuf;

class _ExtensionFieldSet {
  final _FieldSet _parent;
  final Map<int, Extension> _info = <int, Extension>{};
  final Map<int, dynamic> _values = <int, dynamic>{};
  bool _isReadOnly = false;

  _ExtensionFieldSet(this._parent);

  Extension _getInfoOrNull(int tagNumber) => _info[tagNumber];

  _getFieldOrDefault(Extension fi) {
    if (fi.isRepeated) return _getList(fi);
    _validateInfo(fi);
    // TODO(skybrian) seems unnecessary to add info?
    // I think this was originally here for repeated extensions.
    _addInfoUnchecked(fi);
    var value = _getFieldOrNull(fi);
    if (value == null) return fi.makeDefault();
    return value;
  }

  bool _hasField(int tagNumber) {
    var value = _values[tagNumber];
    if (value == null) return false;
    if (value is List) return value.isNotEmpty;
    return true;
  }

  /// Ensures that the list exists and an extension is present.
  ///
  /// If it doesn't exist, creates the list and saves the extension.
  /// Suitable for public API and decoders.
  List<T> _ensureRepeatedField<T>(Extension<T> fi) {
    assert(!_isReadOnly);
    assert(fi.isRepeated);
    assert(fi.extendee == _parent._messageName);

    var list = _values[fi.tagNumber];
    if (list != null) return list as List<T>;

    return _addInfoAndCreateList(fi);
  }

  List<T> _getList<T>(Extension<T> fi) {
    var value = _values[fi.tagNumber];
    if (value != null) return value as List<T>;
    if (_isReadOnly) return List<T>.unmodifiable(const []);
    return _addInfoAndCreateList(fi);
  }

  List _addInfoAndCreateList(Extension fi) {
    _validateInfo(fi);
    var newList = fi._createRepeatedField(_parent._message);
    _addInfoUnchecked(fi);
    _setFieldUnchecked(fi, newList);
    return newList;
  }

  _getFieldOrNull(Extension extension) => _values[extension.tagNumber];

  void _clearFieldAndInfo(Extension fi) {
    _clearField(fi);
    _info.remove(fi.tagNumber);
  }

  void _clearField(Extension fi) {
    _ensureWritable();
    _validateInfo(fi);
    if (_parent._hasObservers) _parent._eventPlugin.beforeClearField(fi);
    _values.remove(fi.tagNumber);
  }

  /// Sets a value for a non-repeated extension that has already been added.
  /// Does error-checking.
  void _setField(int tagNumber, value) {
    var fi = _getInfoOrNull(tagNumber);
    if (fi == null) {
      throw ArgumentError(
          "tag $tagNumber not defined in $_parent._messageName");
    }
    if (fi.isRepeated) {
      throw ArgumentError(_parent._setFieldFailedMessage(
          fi, value, 'repeating field (use get + .add())'));
    }
    _ensureWritable();
    _parent._validateField(fi, value);
    _setFieldUnchecked(fi, value);
  }

  /// Sets a non-repeated value and extension.
  /// Overwrites any existing extension.
  void _setFieldAndInfo(Extension fi, value) {
    _ensureWritable();
    if (fi.isRepeated) {
      throw ArgumentError(_parent._setFieldFailedMessage(
          fi, value, 'repeating field (use get + .add())'));
    }
    _ensureWritable();
    _validateInfo(fi);
    _parent._validateField(fi, value);
    _addInfoUnchecked(fi);
    _setFieldUnchecked(fi, value);
  }

  void _ensureWritable() {
    if (_isReadOnly) frozenMessageModificationHandler(_parent._messageName);
  }

  void _validateInfo(Extension fi) {
    if (fi.extendee != _parent._messageName) {
      throw ArgumentError(
          'Extension $fi not legal for message ${_parent._messageName}');
    }
  }

  void _addInfoUnchecked(Extension fi) {
    assert(fi.extendee == _parent._messageName);
    _info[fi.tagNumber] = fi;
  }

  void _setFieldUnchecked(Extension fi, value) {
    if (_parent._hasObservers) {
      _parent._eventPlugin.beforeSetField(fi, value);
    }
    _values[fi.tagNumber] = value;
  }

  // Bulk operations

  Iterable<int> get _tagNumbers => _values.keys;
  Iterable<Extension> get _infos => _info.values;

  get _hasValues => _values.isNotEmpty;

  bool _equalValues(_ExtensionFieldSet other) =>
      other != null && _areMapsEqual(_values, other._values);

  void _clearValues() => _values.clear();

  /// Makes a shallow copy of all values from [original] to this.
  ///
  /// Repeated fields are copied.
  /// Extensions cannot contain map fields.
  void _shallowCopyValues(_ExtensionFieldSet original) {
    for (int tagNumber in original._tagNumbers) {
      Extension extension = original._getInfoOrNull(tagNumber);
      _addInfoUnchecked(extension);

      final value = original._getFieldOrNull(extension);
      if (value == null) continue;
      if (extension.isRepeated) {
        assert(value is PbListBase);
        _ensureRepeatedField(extension)..addAll(value);
      } else {
        _setFieldUnchecked(extension, value);
      }
    }
  }

  void _markReadOnly() {
    if (_isReadOnly) return;
    _isReadOnly = true;
    for (Extension field in _info.values) {
      if (field.isRepeated) {
        final entries = _values[field.tagNumber];
        if (entries == null) continue;
        if (field.isGroupOrMessage) {
          for (var subMessage in entries as List<GeneratedMessage>) {
            subMessage.freeze();
          }
        }
        _values[field.tagNumber] = entries.toFrozenPbList();
      } else if (field.isGroupOrMessage) {
        final entry = _values[field.tagNumber];
        if (entry != null) {
          (entry as GeneratedMessage).freeze();
        }
      }
    }
  }
}
