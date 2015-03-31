---
layout: post
title: "F# RequiredQualifiedAccessAttribute"
date: 2010-10-12 00:35:49
categories: 1293858726
---
Наверняка многие видели в F# атрибут `[<RequiredQualifiedAccess>]` или натыкались на невозможность открытия модулей `Seq`, `List` и некоторых других с помощью ключевого слова `open`. К примеру, в случае такого определения модуля:

```fsharp
[<RequireQualifiedAccess>]
module Some =
    let foo x = (+) "foo"
    let (==>) = (+) 1
    let (|Even|) x = x % 2 = 0

    type Character = A | B | C
    type Person = { name : string; age : int }
```

Использовать его содержимое можно только следующим образом:

```fsharp
let foo = Some.foo "bar"
let bar = Some.(==>) 1

let (Some.Even a) = 2
let b = match 2 with Some.Even x -> x

let c = Some.A
let p = { Some.name = "Ben"
          Some.age  =  21   }
```

Обратите внимание, что использовать операторы в инфиксной форме становится невозможно. Однако не все знают, что атрибут `[<RequiredQualifiedAccess>]` можно применять к *record* и *union*-типам F#:

```fsharp
[<RequireQualifiedAccess>]
type Character = A | B | C

[<RequireQualifiedAccess>]
type Person = { name : string; age : int }
```

И использовать, явно указывая имя типа, к которому относится union case или record field:

```fsharp
let c = Character.A
let p = { Person.name = "Ben"
          Person.age  =  21   }
```

Это может очень пригодиться, если union или record содержат множество имён case’ов или field’ов, которые могут вступать в конфликт с другими именами из открытых модулей, тем самым создавая неудобства пользователю кода и затрудняя или вовсе делая невозможным вывод типов.