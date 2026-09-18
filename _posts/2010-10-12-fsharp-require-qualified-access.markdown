---
layout: post
title: "F# [RequireQualifiedAccess] attribute"
date: 2010-10-12 00:35:49
author: Aleksandr Shvedov
---
You may have seen the `[<RequireQualifiedAccess>]` attribute in F#, or encountered the restriction that prevents modules such as `Seq` and `List` from being opened with the `open` keyword. For example, consider this module definition:

```fsharp
[<RequireQualifiedAccess>]
module Some =
    let foo x = (+) "foo"
    let (==>) = (+) 1
    let (|Even|) x = x % 2 = 0

    type Character = A | B | C
    type Person = { name : string; age : int }
```

Its members must then be accessed through the module name:

```fsharp
let foo = Some.foo "bar"
let bar = Some.(==>) 1

let (Some.Even a) = 2
let b = match 2 with Some.Even x -> x

let c = Some.A
let p = { Some.name = "Ben"
          Some.age  =  21   }
```

Note that the operator can no longer be used in infix form. Less well known is that `[<RequireQualifiedAccess>]` can also be applied to F# *record* and *union* types:

```fsharp
[<RequireQualifiedAccess>]
type Character = A | B | C

[<RequireQualifiedAccess>]
type Person = { name : string; age : int }
```

Union cases and record fields are then accessed by explicitly qualifying them with the type name:

```fsharp
let c = Character.A
let p = { Person.name = "Ben"
          Person.age  =  21   }
```

This can be useful when a union or record introduces many case or field names that could conflict with names from other open modules. Requiring qualification avoids ambiguity for users of the API and prevents name collisions from complicating or obstructing type inference.