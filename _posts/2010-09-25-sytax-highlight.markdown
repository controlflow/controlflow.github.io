---
layout: post
title: "Sytax highlight"
date: 2010-09-25 14:47:03
categories: 1184444611
---
Мда, tumblr режет теги style в html, придётся использовать syntax highlighter:

{% highlight fsharp %}
(* some string literal *)
let s = "hello, tumblr"

[<EntryPoint>]
let main (args : string array) =
    printfn "%s!" s
    0 // return success code

{% endhighlight %}

Но зато он один из единственных, кто подсвечивает F#, и достаточно симпатишно… Чуток ещё допилить стили и будет нормалёк… :)