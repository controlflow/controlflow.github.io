---
layout: post
title: "F# computation expressions - part 1: maybe { ... }"
date: 2011-01-02 14:17:00
author: Aleksandr Shvedov
tags: fsharp computation expressions monads maybe option
---
Ну как можно не посветить монадам первый пост в новом году?

В этой серии постов я хочу просто собрать в кучу определения на F# таких эпических монад, как `maybe`, `state`, `continuation` и, возможно, некоторых других. Сомневаюсь, что кому-то они реально понадобятся в повседневной разработке на F# (когда есть изменяемые `let`-привязки вместо монады `state` и встроенные в язык `seq { … }`, `[ … ]` и `[| … |]`, а так же `async { … }` из состава стандартной библиотеки), поэтому серия носит чисто академический характер (например, если вам хочется в самых известных монадах, но при этом не хочется курить детали *type classes* или разбирать синтаксис Haskell). Я не буду приводить реализации всех возможных методов классов-builder’ов *computation expression* (перечисление которых и правила трансформации можно найти [здесь](http://msdn.microsoft.com/en-us/library/dd233182.aspx)), а лишь тот набор, который позволят понять суть монады и пример её использования.

Начнём с монады `maybe`, а в качестве типа вычисления `M<’a>` будем использовать тип `Option<’a>` из стандартной библиотеки F#. Сигнатура:

```fsharp
namespace FSharp.Monads

type MaybeBuilder =
  new: unit -> MaybeBuilder
  member Zero: unit -> 'a option
  member Bind: 'a option * ('a -> 'b option) -> 'b option
  member Return: 'a -> 'a option
  member ReturnFrom: 'a option -> 'a option
```

Реализация:

```fsharp
namespace FSharp.Monads

type MaybeBuilder() =
  member b.Zero() = None
  member b.Bind(x, f) =
    match x with Some x -> f x
               | None   -> None
  member b.Return x = Some x
  member b.ReturnFrom x = x : _ option
```

В качестве пример использования, можно привести программу, которая ожидает ввод пользователем целого числа и пытается найти порядковый номер введённого числа в последовательности простых чисел, при этом в случае не числового ввода или ввода числа, не являющегося простым, программа останавливается и возвращает `None`:

```fsharp
open System
open FSharp.Monads

let maybe = MaybeBuilder()

/// Список простых чисел от 2 до 100
let primes =
  let is_prime x = // неэффективно, лишь для примера
    Seq.forall (fun y -> x % y > 0) { 2 .. x/2 }
  { 2 .. 100 } |> Seq.filter is_prime
               |> Seq.toList

/// Попытка считывания с консоли целого числа
let inputInt32() =
  maybe {
   let str = Console.ReadLine()
   let success, value = Int32.TryParse str
   if success then return value
  }

/// Попытка считывания с консоли простого числа
let tryInputPrime() =
  maybe {
    printfn "введите простое число от 2 до 100:"
    let! prime = inputInt32()
    let! index = List.tryFindIndex ((=) prime) primes
    return prime, index + 1
  }

match tryInputPrime() with
| Some(prime, index) ->
          printfn "ввели простое число %d (№%d)" prime index
| None -> printfn "ввод простого числа завершился неудачей"
```

Вот как выглядит функция `inputInt32` “без сахара”, обратите внимание на вызов метода `Zero()`:

```fsharp
/// Попытка считывания с консоли целого числа
let inputInt32'() =
  let str = Console.ReadLine()
  let success, value = Int32.TryParse str
  if success
    then maybe.Return(value)
    else maybe.Zero()
```

А вот и вся “поднаготная” функции `tryInputPrime`:

```fsharp
/// Попытка считывания с консоли простого числа
let tryInputPrime'() =
  printfn "введите простое число от 2 до 100:"
  maybe.Bind(
    inputInt32(),
    fun prime ->
      maybe.Bind(
        List.tryFindIndex ((=) prime) primes,
        fun index ->
          maybe.Return(prime, index + 1)))
```

Обратите так же внимание на модуль `Option` из состава стандартной библиотеки F#, он содержит дополнительные функции для работы со значениями типа `'a option`, такие как `map` и `fold` и другие.