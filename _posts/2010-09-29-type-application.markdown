---
layout: post
title: "Type Application"
date: 2010-09-29 13:32:51
categories: 1209803041
tags: fsharp generics
---
Забавно, в F# можно применить к не обобщённым типам/функциям пустой список типов-аргументов:

{% highlight fsharp %}
let succ = (+) 1
let two = succ< > 1

{% endhighlight %}

Причём наличие пробела между фигурными скобками обязательно. Не понятно почему это разрешено :)