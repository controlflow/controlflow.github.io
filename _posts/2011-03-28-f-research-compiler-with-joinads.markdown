---
layout: post
title: "F# Research Compiler with Joinads!"
date: 2011-03-28 23:08:00
author: Aleksandr Shvedov
tags: fsharp joinads expreremental compiler computation expressions monads
---
Совсем недавно Tomas Petricek выложил в свет (оригинальный пост [здесь](http://tomasp.net/blog/fsharp-variations-joinads.aspx)) эксперементальную сборку компилятора F# 2.0, поддерживающую механизм под названием *joinads*, а так же некоторые дополнительные модификации.

Основная информация о механизме “джоинад” есть в публикации *"Reactive, parallel and concurrent programming in F#"* (pdf [здесь](http://tomasp.net/academic/joinads/joinads.pdf)), описывающей области применения, необходимые расширения синтаксиса F# computation expressions, правила трансформации кода (однако реальные правила трансформации кода несколько отличаются от изложенных в публикации, например, `Choose` не получает на вход список, а используюся несколько вложенных друг в друга вызовов `Choose`).

Например, так выглядит код использования джоинады `future`, запускающий несколько параллельных задач и ожидающих их результатов:

```fsharp
let parallelOr = future {
  match! (after 1000 true), (after 100 true) with
  | !true, _ -> return true
  | _, !true -> return true
  | !a, !b -> return a || b
}
```

Если любая из задач возвратит `true`, то всё выражение сразу будет вычислено как `true`. В случае, если любая из задач возвратит `false`, будет произведено ожидание результата другой задачи и выражение будет вычислено как логическое `||` результатов обоих задач (третий кейс).

Дополнительно эксперементальный компилятор поддерживает механизм “идиом” (аппликативных функторов из мира haskell) с помощью использования синтаксиса `let! … and` внутри computation expressions. Подробнее про идиомы можно прочитать в том же блоге Томаса - [1](http://tomasp.net/blog/idioms-in-linq.aspx) и [2](http://tomasp.net/blog/formlets-in-linq.aspx) (если не напрягает query syntax C#, конечно).

Следует предупредить, что новые ключевые слова и конструкции, такие как `match!`, поддерживаются на уровне компилятора и интерактивной консоли F#, однако использование данный расширений непосредственно в Visual Studio затруднительно, так как студия использует собственные парсер и модель кода F# - вы будете получать море синтаксических ошибок, однако код будет компилироваться и исправно запускаться.

Скачать модифицированный компилятор можно здесь: [сборка](http://tomasp.net/articles/fsharp-joinads/fsharp-joinads.zip) (zip, 7mb), [исходный код](https://github.com/tpetricek/Fsharp.Extensions) (для mono). Помимо этого, [здесь](https://github.com/tpetricek/Documents/tree/master/Blog%202011/Joinads) доступны примеры реализаций джоинад `future` и `maybe`, а так же идиомы `ziplist`.