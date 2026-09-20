// GENERATED CODE - DO NOT MODIFY BY HAND

import 'package:re_highlight/re_highlight.dart';

final langzig = Mode(
    name: "Zig",
    keywords: {
      "keyword": [
        "inline",
        "while",
        "for",
        "extern",
        "packed",
        "export",
        "pub",
        "noalias",
        "comptime",
        "volatile",
        "align",
        "linksection",
        "threadlocal",
        "allowzero",
        "noinline",
        "callconv",
        "struct",
        "enum",
        "const",
        "union",
        "opaque",
        "asm",
        "unreachable",
        "break",
        "return",
        "continue",
        "defer",
        "errdefer",
        "await",
        "resume",
        "suspend",
        "async",
        "nosuspend",
        "try",
        "catch",
        "if",
        "else",
        "switch",
        "orelse",
        "usingnamespace",
        "test",
        "and",
        "or",
        "bool",
        "void",
        "type",
        "blk"
      ],
      "literal": [
        "true",
        "false",
        "null",
        "undefined"
      ],
      "built_in": [
        "std",
        "meme",
        "@This",
        "@Import",
        "@ass",
        "i8",
        "i16",
        "i32",
        "i64",
        "i128",
        "u8",
        "u16",
        "u32",
        "u64",
        "u128",
        "f16",
        "f32",
        "f64",
        "usize",
        "isize",
        "c_short",
        "c_int",
        "c_long",
        "c_longlong",
        "c_ushort",
        "c_uint",
        "c_ulong",
        "c_ulonglong",
        "c_float",
        "c_double",
        "c_void",
        "mem"
      ],
      "type": [
        "anytype",
        "noreturn",
        "error",
        "anyerror",
        "anyframe",
        "anyopaque"
      ],
      "operator": [
        "+",
        "-",
        "*",
        "/",
        "%",
        "==",
        "!=",
        "<",
        ">",
        "<=",
        ">="
      ]
    },
    illegal: "\\/\\*",
    contains: <Mode>[
      // Built-in: mem.Copy
      Mode(
          className: "built_in",
          begin: "\\bmem\\.Copy\\b"),

      // Meta-event: |something|
      Mode(
          className: "meta-event",
          begin: "\\|[a-zA-Z_]+\\|"),

      Mode(
          className: "comment-todo",
          begin: "\\/\\/\\s*TODO:.*\$"),

      // Single-line comments
      Mode(
          className: "comment",
          begin: "\\/\\/[^\\n]*"),

      C_LINE_COMMENT_MODE,

      // Error handling operator: !type
      Mode(
          className: "errorhandling",
          begin: "!(?=\\w+)"),

      // Optional types / parameters: ?Type
      Mode(
          className: "optional",
          begin: "\\?(?=[a-zA-Z_])"),

      // Zig operators
      Mode(
          className: "operator",
          begin: "[-+%/*=<>!]=?|&&|\\|\\||<<=?|>>=?|\\*\\*|\\+\\+|--|\\->"),

      // Property access
      Mode(
          className: "property",
          begin: "\\.\\w+"),

      // Strings
      QUOTE_STRING_MODE,
      APOS_STRING_MODE,

      // Numbers
      C_NUMBER_MODE,

      // Zig @ builtins / identifiers
      Mode(
          className: "string",
          begin: "@[a-zA-Z_]\\w*"),

      Mode(
          className: "meta",
          begin: "@[a-zA-Z_]\\w*"),

      // Quoted symbols
      Mode(
          className: "symbol",
          begin: "'[a-zA-Z_][a-zA-Z0-9_]*'"),

      // Escape sequences
      Mode(
          className: "literal",
          begin: "\\\\[xuU][a-fA-F0-9]+"),

      // Hexadecimal numbers
      Mode(
          className: "number",
          begin: "\\b0x[0-9a-fA-F]+"),

      // Binary numbers
      Mode(
          className: "number",
          begin: "\\b0b[01]+"),

      // Octal numbers
      Mode(
          className: "number",
          begin: "\\b0o[0-7]+"),

      // Decimal numbers
      Mode(
          className: "number",
          begin: "\\b[0-9]+\\b"),

      // Regular expressions
      REGEXP_MODE,

      // Function declarations
      Mode(
          className: "function",
          beginKeywords: "fn",
          end: "\\{",
          excludeEnd: true,
          contains: <Mode>[
            Mode(
                className: "title",
                begin: "[a-zA-Z_][a-zA-Z0-9_]*"),

            Mode(
                className: "params",
                begin: "\\(",
                end: "\\)",
                endsParent: true,
                contains: <Mode>[
                  C_LINE_COMMENT_MODE,
                  C_BLOCK_COMMENT_MODE
                ])
          ]),

      // Function calls
      Mode(
          className: "function-call",
          begin: "[a-zA-Z_][a-zA-Z0-9_]*\\(",
          end: "\\)",
          excludeEnd: true,
          contains: <Mode>[
            Mode(
                className: "params",
                begin: "\\(",
                end: "\\)",
                contains: <Mode>[
                  C_LINE_COMMENT_MODE,
                  C_BLOCK_COMMENT_MODE
                ])
          ]),

      // @macro calls
      Mode(
          className: "macro",
          begin: "@[a-zA-Z_][a-zA-Z0-9_]*"),

      // Multiline string literals
      //
      // Zig multiline strings begin with a backslash at the
      // beginning of a line and continue until the line ends.
      Mode(
          className: "multiline",
          begin: "\\\\",
          end: "\$",
          relevance: 0,
          contains: <Mode>[
            Mode(
                begin: "\\\\",
                end: "\$",
                relevance: 0)
          ])
    ]);