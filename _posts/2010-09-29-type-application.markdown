---
layout: post
title: "Type Application"
date: 2010-09-29 13:32:51
tags: fsharp generics
---
Забавно, в F# можно применить не обобщённые типы/функции к пустому списку типов-аргументов:

```fsharp
let succ = (+) 1
let two = succ< > 1
```

Причём наличие пробела между фигурными скобками обязательно. Не понятно почему это разрешено :)