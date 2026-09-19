---
layout: post
title: "F# [StructuredFormatDisplay] attribute"
date: 2011-01-18 21:10:00
author: Aleksandr Shvedov
tags: fsharp printf sprintf StructuredFormatDisplayAttribute
---
A short post about a little-known attribute in the F# standard library: `StructuredFormatDisplayAttribute`. It controls how values are formatted with the `%A` format specifier (in `printf`, `sprintf`, and other functions in the `Printf` module), as well as how values of the type appear in F# Interactive. If you define a custom type like this:

```fsharp
type Person(name: string, age: int, money: decimal) =
  member __.Name  = name
  member __.Age   = age
  member __.Money = money

let alex = Person("Alex", 22, 200000m)
```

Instances of the type will appear in F# Interactive as follows:

    val alex : Person = FSI.Person

Overriding `System.Object.ToString()` lets you see the object's internal state in the interactive console: both F# Interactive and `%A` use a `ToString()` override when one is available:

```fsharp
type Person(name: string, age: int, money: decimal) =
  member __.Name  = name
  member __.Age   = age
  member __.Money = money
  override __.ToString() =
    sprintf "Person(%s, %d, %O)" name age money

let alex = Person("Alex", 22, 200000m)
```

Output:

    val alex : Person = Person(Alex, 22, 200000M)

Sometimes, though, the text returned by `ToString()` is not what you want to see in F# Interactive or when formatting a value with `%A`. The `[<StructuredFormatDisplay>]` attribute lets you specify a separate display format. Its format string has the form `"Prefix {PropertyName} Suffix"`, where `Prefix` and `Suffix` are optional literal text, and `PropertyName` is the name of a property defined in the type or one of its base classes:

```fsharp
[<StructuredFormatDisplay("Person (with Name='{Name}')")>]
type Person(name: string, age: int, money: decimal) =
  member __.Name  = name
  member __.Age   = age
  member __.Money = money
  override __.ToString() =
    sprintf "Person(%s, %d, %O)" name age money

let alex = Person("Alex", 22, 200000m)
```

The output now looks like this:

    val alex : Person = Person (with Name='Alex')

The format string can refer to only *one* property. Literal `{` and `}` characters are not supported, even when escaped as {% raw %}`{{` and `}}`{% endraw %}. Properties declared `private` are supported.