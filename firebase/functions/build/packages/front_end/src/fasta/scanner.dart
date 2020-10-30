// Copyright (c) 2016, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE.md file.

library fasta.scanner;

import 'dart:convert' show unicodeReplacementCharacterRune, utf8;

import '../scanner/token.dart' show Token;

import 'scanner/abstract_scanner.dart'
    show LanguageVersionChanged, ScannerConfiguration;

import 'scanner/string_scanner.dart' show StringScanner;

import 'scanner/utf8_bytes_scanner.dart' show Utf8BytesScanner;

import 'scanner/recover.dart' show scannerRecovery;

export 'scanner/abstract_scanner.dart'
    show LanguageVersionChanged, ScannerConfiguration;

export 'scanner/token.dart'
    show
        LanguageVersionToken,
        StringToken,
        isBinaryOperator,
        isMinusOperator,
        isTernaryOperator,
        isUnaryOperator,
        isUserDefinableOperator;

export 'scanner/error_token.dart'
    show ErrorToken, buildUnexpectedCharacterToken;

export 'scanner/token.dart' show LanguageVersionToken;

export 'scanner/token_constants.dart' show EOF_TOKEN;

export 'scanner/utf8_bytes_scanner.dart' show Utf8BytesScanner;

export 'scanner/string_scanner.dart' show StringScanner;

export '../scanner/token.dart' show Keyword, Token;

const int unicodeReplacementCharacter = unicodeReplacementCharacterRune;

typedef Token Recover(List<int> bytes, Token tokens, List<int> lineStarts);

abstract class Scanner {
  /// Returns true if an error occurred during [tokenize].
  bool get hasErrors;

  List<int> get lineStarts;

  /// Configure which tokens are produced.
  set configuration(ScannerConfiguration config);

  Token tokenize();
}

class ScannerResult {
  final Token tokens;
  final List<int> lineStarts;
  final bool hasErrors;

  ScannerResult(this.tokens, this.lineStarts, this.hasErrors);
}

/// Scan/tokenize the given UTF8 [bytes].
ScannerResult scan(List<int> bytes,
    {ScannerConfiguration configuration,
    bool includeComments: false,
    LanguageVersionChanged languageVersionChanged}) {
  if (bytes.last != 0) {
    throw new ArgumentError("[bytes]: the last byte must be null.");
  }
  Scanner scanner = new Utf8BytesScanner(bytes,
      configuration: configuration,
      includeComments: includeComments,
      languageVersionChanged: languageVersionChanged);
  return _tokenizeAndRecover(scanner, bytes: bytes);
}

/// Scan/tokenize the given [source].
ScannerResult scanString(String source,
    {ScannerConfiguration configuration,
    bool includeComments: false,
    LanguageVersionChanged languageVersionChanged}) {
  assert(source != null, 'source must not be null');
  StringScanner scanner = new StringScanner(source,
      configuration: configuration,
      includeComments: includeComments,
      languageVersionChanged: languageVersionChanged);
  return _tokenizeAndRecover(scanner, source: source);
}

ScannerResult _tokenizeAndRecover(Scanner scanner,
    {List<int> bytes, String source}) {
  Token tokens = scanner.tokenize();
  if (scanner.hasErrors) {
    if (bytes == null) bytes = utf8.encode(source);
    tokens = scannerRecovery(bytes, tokens, scanner.lineStarts);
  }
  return new ScannerResult(tokens, scanner.lineStarts, scanner.hasErrors);
}
