---
layout: post
title: "F# infoof (part 3)"
date: 2010-11-20 18:51:00
categories: 1627204212
tags: fsharp pattern-matching patterns infoof
---
Наш модуль осталось дополнить лишь такими функциями, как `fieldinfo` (реализация практически идентична `propertyinfo`), `constructorof` (получение `System.Reflection.` `ConstructorInfo` по выражению создания экземпляров объектов) и `unioncaseof` (получение `Microsoft.FSharp.Reflection.UnionCaseInfo` по выражению вызова конструктора типа-объдинения F#). Все они достаточно тривиальны, поэтому лишь привожу окончательную реализацию модуля `MemberInfo`.

Сигнатура модуля:

```fsharp
module MemberInfo

open Microsoft.FSharp.Quotations
open Microsoft.FSharp.Reflection
open System.Reflection

val fieldof       : Expr -> FieldInfo
val propertyof    : Expr -> PropertyInfo
val methodof      : Expr -> MethodInfo
val methoddefof   : Expr -> MethodInfo
val constructorof : Expr -> ConstructorInfo
val unioncaseof   : Expr -> UnionCaseInfo
val eventof       : Expr -> EventInfo
```

Реализация модуля:

```fsharp
module MemberInfo

open Microsoft.FSharp.Quotations.Patterns
open Microsoft.FSharp.Quotations.DerivedPatterns
open System.Reflection

/// Получение FieldInfo по выражению доступа к полю
let fieldof expr =
  match expr with
    | FieldGet(_, info) -> info
    | Lambda(arg, FieldGet(Some(Var var), info))
    | Let(arg, _, FieldGet(Some(Var var), info))
        when arg = var -> info
    | _ -> failwith "Not a field expression"

/// Получение PropertyInfo по выражению доступа к свойству
let propertyof expr =
  match expr with
    | PropertyGet(_, info, _) -> info
    | Lambda(arg, PropertyGet(Some(Var var), info, _))
    | Let(arg, _, PropertyGet(Some(Var var), info, _))
        when arg = var -> info
    | _ -> failwith "Not a property expression"

/// Образец, совпадающий со значением функционального
/// типа, сгенерированным F# из метода или функции
let private (|Func|_|) expr =
  let onlyVar = function Var v -> Some v | _ -> None
  match expr with
    // функ.значения без аргументов
    | Lambda(arg, Call(target, info, []))
        when arg.Type = typeof<unit> -> Some(target, info)

    // функ.значения с одним аргументом
    | Lambda(arg, Call(target, info, [ Var var ]))
        when arg = var -> Some(target, info)

    // функ.значения с набором каррированных
    // или взятых в кортеж аргументов
    | Lambdas(args, Call(target, info, exprs))
        when List.choose onlyVar exprs
           = List.concat args -> Some(target, info)

    | _ -> None

/// Получение MethodInfo по выражению вызова метода
/// или выражению значения функционального типа
let methodof expr =
  match expr with
    // любые обычные вызовы: foo.Bar()
    | Call(_, info, _) -> info

    // вызовы и функ.значения через аргумент лямбды:
    // fun (x: string) -> x.Substring(1, 2)
    // fun (x: string) -> x.StartsWith
    | Lambda(arg, Call(Some(Var var), info, _))
    | Lambda(arg, Func(Some(Var var), info))
        when arg = var -> info

    // любые функциональные значения:
    // someString.StartsWith
    | Func(_, info) -> info

    // вызовы и функ.значения через экземпляры:
    // "abc".StartsWith("a")
    // "abc".Substring
    | Let(arg, _, Call(Some (Var var), info, _))
    | Let(arg, _, Func(Some (Var var), info))
        when arg = var -> info

    | _ -> failwith "Not a method expression"

/// Получение generic method definition по выражению
/// вызова generic-метода или выражению значения
/// функционального типа
let methoddefof expr =
  match methodof expr with
    | info when info.IsGenericMethod ->
                info.GetGenericMethodDefinition()
    | info -> failwithf "%A is not generic" info

/// Получение ConstructorInfo по выражению
/// создания нового объекта или записи F#
let constructorof expr =
  match expr with
    | NewObject(info, _) -> info

    // Получения конструктора record'а
    | NewRecord(recordType, _) ->
        match recordType.GetConstructors() with
        | [| info |] -> info
        | _ -> failwith "Invalid record type"

    | _ -> failwith "Not a constructor expression"

/// Получение EventInfo по выражению
/// доступа к CLI-совместимому событию
let eventof expr =
  match expr with
    | Call(None, createEvent, [
            Lambda(arg1, Call(_,    addHandler, [ Var var1 ]))
            Lambda(arg2, Call(_, removeHandler, [ Var var2 ]))
            Lambda(_, NewDelegate _)
          ])
      when createEvent.Name = "CreateEvent"
        &&    addHandler.Name.StartsWith("add_")
        && removeHandler.Name.StartsWith("remove_")
        && arg1 = var1
        && arg2 = var2 ->
           addHandler.DeclaringType.GetEvent(
               addHandler.Name.Remove(0, 4),
               BindingFlags.Public ||| BindingFlags.Instance |||
               BindingFlags.Static ||| BindingFlags.NonPublic)

    | _ -> failwith "Not a event expression"

/// Получение UnionCaseInfo по выражению вызова
/// или проверки конструктора union-типа
let unioncaseof expr =
  match expr with
    | NewUnionCase(info, _)
    | UnionCaseTest(_, info) -> info
    | _ -> failwith "Not a union case expression"
```