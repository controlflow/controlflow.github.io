---
layout: post
title: "Types and Programming Languages». Benjamin C. Pierce"
date: 2016-09-04 10:00:00
author: Aleksandr Shvedov
tags: tapl typesystems types
---

<img alt="tapl" src="/images/tapl.jpg" style="float: left; margin-right: 1em" width="45%" />

I’ll say this upfront: this book isn’t for every programmer. It’s full of "math" or "formulas" (such as typing and evaluation rules), and full of theorem prooving exercises. Similar to scientific papers, the amount of useful information in a single sentence can sometimes be overwhelming. At the start of each chapter or the book, a bunch of symbols are introduced, which are then used extensively without further explanation, making sentences feel like they’re "obfuscated." But we’re not afraid of complexity, are we?

I had heard about this book for a long time, but I only got my hands on a physical copy while exploring the functional programming paradigm and tinkering with the F# language. Looking at a paradigm that was new to me and an unusual type system (compared to C#) sparked my interest in learning more about what type systems can offer and how different solutions compare. Without a doubt, Types and Programming Languages (TAPL) is a must-have reference for anyone interested in the theory of type systems, developing compilers, or building tools for programming languages.

To even begin to grasp the content of TAPL, you’ll need to familiarize yourself with the basics of untyped and typed lambda calculus (Chapters I and II), learn how to write typing and evaluation rules (these intimidating "formulas" are much simpler than they seem at first!), and get comfortable with the syntax of an ML-like language. Without this minimal "survival kit", half the book will feel like it’s written in an alien language, so make sure to prepare with some theoretical groundwork.

For .NET programmers, Chapter III — "Subtyping" — might be the most useful, as it essentially describes classic class-based object-oriented programming. The book explains why subtyping exists and answers a host of fundamental questions we often don’t even think about, such as:

* What is the type `Object`, and what type “opposite” to `Object` type is missing in languages like C#/Java? How do you assign a type for a function that never terminates (throws an exception)?

* How do structural and nominal (or "name-based") type systems with subtyping differ? Why, for example, does TypeScript use a structural type system to type-check JavaScript code?

* Why do OOP languages have different kinds of type casting, and what is the purpose of each?

* What is the purpose of boxed values, and why is a universal memory representation of values needed?

* Why can subtypes be thought of as sets, but a different semantics is used in practice?

* How do traditional classes in OOP differ from algebraic data types (ADTs, used in most functional programming languages), and what are the pros and cons of each?

* What are union types and intersection types, which are becoming popular in languages like TypeScript, Scala (Dotty), and Ceylon? In what form are intersection types found in C#/Java?

TAPL provides concise answers to these and many other questions, vastly different from the typical presentation of OOP in books. Analyzing an imperative OOP language with subtyping using simple typed lambda calculus is like studying a high-level language through a bytecode decompiler (many programmers do this — it’s a great way to understand how something works).

Note on Russian translation of TAPL book:

Я не склонен читать подобную литературу на русском языке, но благодаря замечательной работе, проделанной Георгием Бронниковым и Алексом Оттом (издательство «Лямбда пресс» & «Добросвет»), перевод TAPL — это исключение, можно совсем не беспокоиться об искажении смысла или терминов.