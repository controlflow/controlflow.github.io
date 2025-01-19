---
layout: post
title: "Мемоизация выражений F# + синтаксис computation expressions"
date: 2010-12-30 16:57:00
author: Aleksandr Shvedov
tags: fsharp memoize expressions compiler comparer equality computation expressions
---
Сегодня предлагаю вашему вниманию ещё один, наиболее извращённый способ мемоизации в F#. Цель - получить удобный синтаксис для выделения частей функций, подвергаемых мемоизации без явного указания параметров, например:

```fsharp
let doWork x y =
  // ...
  let result = memo {
    // подвергаемые мемоизации вычисления,
    // зависящие от значений x и y
    return x + y
  }

  // ...
  result + 1
```

Давайте перепишем код выше следующим образом:

```fsharp
let doWork' x y =
  // ...
  let f = (fun() ->
    // подвергаемые мемоизации вычисления,
    // зависящие от значений x и y
    x + y)

  let result = f ()

  // ...
  result + 1
```

То есть обернём мемоизируемое выражение в лямбда-выражение без аргументов и тут же его вызовем. Если посмотреть под Reflector’ом код выше, то можно обнаружить, что компилятор F# генерирует класс-наследник `FSharpFunc<TArg, TResult>` такого вида:

```c#
[Serializable]
internal class f@44 : FSharpFunc<Unit, int> {
  public int x;
  public int y;

  internal f@44(int x, int y) {
    this.x = x;
    this.y = y;
  }

  public override int Invoke(Unit unitVar0) {
    return (this.x + this.y);
  }
}
```

То есть все параметры мемоизации (значения, на которых мы замкнулись) становятся полями этого класса. Вопрос: почему бы не хранить экземпляры данного класса как ключи кэша, ведь они как раз хранят весь набор параметров мемоизации?

Проблема заключается лишь в том, что для данного класса не определены две важные операции: проверка на эквивалентность и вычисления значения хэша. Однако, реализация класса `System.Collections.Generic.Dictionary<TKey, TValue>` поддерживает при создании задание пользовательского компаратора ключей, реализующего интерфейс `IEqualityComparer<’T>`. То есть чтобы осуществить наш сумасшедший план, надо в рантайме получить этот компаратор для произволного класса, сгенерированного F# для представления значений функционального типа - это можно сделать, воспользовавшись динамической компиляцией делегатов с помощью классов из пространства имён `System.Linq.Expressions`.

А автоматическое оборачивание в `(fun() -> …)` возможно, при определении в классе-builder’е [computation expression](http://blogs.msdn.com/b/dsyme/archive/2007/09/22/some-details-on-f-computation-expressions-aka-monadic-or-workflow-syntax.aspx) метода `Delay(f: unit -> ‘T)`. Такой код:

```fsharp
let result = memo {
  return x + y
}
```

Раскрывается компилятором как:

```fsharp
let result = 
  memo.Delay(fun() -> x + y)
```

Без лишних слов привожу сигнатуру модуля `ComparerCompiler`, предназначенного для компилирования компаратора по типу и набору его полей:

```fsharp
module ComparerCompiler

open System.Collections.Generic
open System.Reflection

[<RequiresExplicitTypeArguments>]
val compile: FieldInfo[] -> IEqualityComparer<'T>
```

И его реализацию:

```fsharp
/// Модуль с функциями для компилирования компараторов
/// экземпляров заданных типов по набору полей
module ComparerCompiler

open System
open System.Collections.Generic
open System.Linq.Expressions
open System.Reflection

/// Заранее вычисленные данные для рефлексии
let eqComparerType  = typedefof<_ EqualityComparer>
let eqComparerIface = typedefof<_ IEqualityComparer>
let getHashMethod = typeof<obj>.GetMethod "GetHashCode"
let func2xType = typedefof<Func<_,_>>
let func3xType = typedefof<Func<_,_,_>>

/// Компилирование делегатов методов Equals и GetHashCode
/// для компараторов типа typ по набору полей fields
let emit (t: Type) (fields: FieldInfo[]) =
  // выражения параметров делегатов
  let x = Expression.Parameter(t, "x")
  let y = Expression.Parameter(t, "y")

  // для всех сравниваемых полей формируем пары выражений
  // проверки на эквивалентность и вычисления хэш-значения
  fields |> Array.map (fun field ->
    let typ = field.FieldType // выбираем тип поля

    let comparer = // получаем экземпляр компаратора
      eqComparerType  // по-умолчанию для типа typ
        .MakeGenericType([| typ |])
        .GetProperty("Default")
        .GetValue(null, null)

    let equalsMethod =  // получаем метод Equals из
      eqComparerIface // типа интерфейса компаратора
        .MakeGenericType([| typ |])
        .GetMethod("Equals")

    // формируем выражение доступа к полю
    let fieldAccess = Expression.Field(x, field)

    // формируем вызов метода `Equals(значение_поля)`
    // через экземпляр компаратора по-умолчанию
    Expression.Call(
      Expression.Constant(comparer),
      equalsMethod, fieldAccess,
      Expression.Field(y, field)) :> Expression,

    // формируем вызов `значение_поля.GetHashCode()`
    let hashCall: Expression =
      upcast Expression.Call(fieldAccess, getHashMethod)

    // для ref-типов добавляем проверку ссылки на null
    if typ.IsValueType then hashCall
    else upcast Expression.Condition(
           Expression.Equal( // if (значение_поля = null)
             fieldAccess, Expression.Constant(null, typ)),
           Expression.Constant(0), // then 0
           hashCall)) // else значение_поля.GetHashCode()

  |> function // проверяем количество полученных пар
    | [|   |] -> raise (ArgumentOutOfRangeException "fields")
    | [| x |] -> x
    | list -> // если их более одной, то агрегируем выражения
      list |> Array.reduce (fun (eq1, hash1) (eq2, hash2) ->
        // проверку на эквивалентность - через && (ленивый)
        upcast Expression.AndAlso(eq1, eq2),
        // вычисления хэша - по формуле: (h1 << 5) ^ h2
        upcast Expression.ExclusiveOr(
          Expression.LeftShift(hash1, Expression.Constant(5)), hash2))

  |> fun (eqBody, hashBody) -> // компилируем
    // формируем типы делегатов
    let eqType = func3xType.MakeGenericType(t, t, typeof<bool>)
    let hashType = func2xType.MakeGenericType(t, typeof<int>)
 
    // компилируем тела делегатов из выражений
    Expression.Lambda(eqType, eqBody, x, y).Compile(),
    Expression.Lambda(hashType, hashBody, x).Compile()

/// Возвращает компаратор экземпляров типа 'T по набору полей
/// из массива fields. Компаратор дополнительно реализует
/// интерфейс System.Collections.IEqualityComparer
[<RequiresExplicitTypeArguments>]
let compile<'T> (fields: FieldInfo[]) =
  if fields = null then
    raise (ArgumentNullException "fields")

  // компилируем тела Equals и GetHashCode
  let eq, hash = emit typeof<'T> fields

  // и приводим к типизированным типам делегатов
  let equality : Func<_,_,_> = downcast eq
  let hashCode : Func<_,_>   = downcast hash

  // возвращаем анонимный компаратор
  { new IEqualityComparer<'T> with
      member __.Equals(x, y) = equality.Invoke(x, y)
      member __.GetHashCode(x) = hashCode.Invoke(x)

    // дополнительная реализация интерфейса
    interface Collections.IEqualityComparer with
      member __.Equals(x, y) =
          match x, y with
          _ when obj.ReferenceEquals(x, y) -> true
        | null, _ | _, null -> false
        | (:? 'T as x),(:? 'T as y) -> equality.Invoke(x,y)
        | _ -> raise (ArgumentException "invalid type")

      member __.GetHashCode(x) =
          match x with
          null -> 0
        | :? 'T as x -> hashCode.Invoke(x)
        | _ -> raise (ArgumentException "invalid type") }
```

Сигнатуру модуля мемоизации:

```fsharp
module MemoBuilder

type MemoBuilder<'T> =
  new: unit -> MemoBuilder<'T>
  member inline Return: 'T -> 'T
  member Delay: (unit -> 'T) -> 'T

val inline memo<'a> : MemoBuilder<'a>
```

И его реализацию:

```fsharp
module MemoBuilder

open System
open System.Collections.Generic

let PrivateStatic =
  Reflection.BindingFlags.NonPublic ||| Reflection.BindingFlags.Static

type MemoBuilder<'T>() =
  // кэш мемоизированных функций (по типам f)
  [<ThreadStatic>][<DefaultValue>]
  static val mutable private cache: Dictionary<Type, (unit -> 'T) -> 'T>

  // свойство для безопасного обращения к кэшу
  member __.FuncCache =
    if MemoBuilder<'T>.cache = null then
      MemoBuilder<'T>.cache <- Dictionary()
    MemoBuilder<'T>.cache

  // заранее вычисленные данные
  static let selfType = typeof<MemoBuilder<'T>>
  static let cacher = selfType.GetMethod("Cache", PrivateStatic)

  // при возвращаении значения из memo { }
  // не делаем ровным счётом ничего
  member inline __.Return(x: 'T) = x

  // главная логика: откладывание вычисления
  member __.Delay(f: unit -> 'T) =
    let typ = f.GetType() // тип мемоизируемой функции
    match __.FuncCache.TryGetValue typ with
    | true, memo -> memo f
    | _ -> // вызываем генератор мемоизатора с типом функции
           // в качестве типа-параметра метода
           let memo = downcast cacher.MakeGenericMethod(typ)
                                     .Invoke(null, null)
           __.FuncCache.Add(typ, memo) // сохраняем тип в кэш
           memo f // пропускаем функцию через мемоизатор

  // генератор мемоизатора по типу функции 'F
  static member Cache<'F when 'F :> FSharpFunc<unit, 'T>>() =
    let t = typeof<'F> // тип функции

    // отбираем поля, учавствующие в замыкании,
    // за исключением замыкания на сам builder
    let fields = t.GetFields()
              |> Array.filter (fun fi -> fi.FieldType <> selfType)

    // компилируем компаратор замыканий
    let comparer = ComparerCompiler.compile<'F> fields

    // и создаём кэш с этим компаратором
    let cache = Dictionary<'F, 'T>(comparer)

    // возвращаем функцию-мемоизатор
    fun (f: FSharpFunc<_,_>) ->
      match cache.TryGetValue (downcast f) with
      | true, result -> result
      | _ -> let result = f.Invoke()
             cache.Add(downcast f, result)
             result

/// Построитель мемоизированного выражения
let inline memo<'a> = MemoBuilder<'a>()
```

И, наконец, пример использования мемоизатора:

```fsharp
open MemoBuilder

let func x y z =
  printfn "func %d %d %d ->" x y z

  let a = memo {
    printfn "  eval a = %d + %d" x y
    // сложные вычисления,
    // замыкающиеся на значения x и y
    return x + y
  }

  let b = memo {
    printfn "  eval b = %d + %d" y z
    // сложные вычисления,
    // замыкающиеся на значения y и z
    return y + z
  }

  let c = memo {
    printfn "  eval c = %d + %d" a b
    // сложные вычисления,
    // замыкающиеся на значения a и b
    return a + b
  }

  printfn "  return %d\n" c

func 1 2 3
func 4 2 3
func 1 2 4
func 2 1 5
func 2 1 5
func 2 1 5
```

Вывод:

    func 1 2 3 ->
      eval a = 1 + 2
      eval b = 2 + 3
      eval c = 3 + 5
      return 8
    
    func 4 2 3 ->
      eval a = 4 + 2
      eval c = 6 + 5
      return 11
    
    func 1 2 4 ->
      eval b = 2 + 4
      eval c = 3 + 6
      return 9
    
    func 2 1 5 ->
      eval a = 2 + 1
      eval b = 1 + 5
      return 9
    
    func 2 1 5 ->
      return 9
    
    func 2 1 5 ->
      return 9

Естественно, я не рекомендую пользоваться этим велосипедом с компиляцией в серьёзных проектах, цель поста - лишь *proof of concept*.