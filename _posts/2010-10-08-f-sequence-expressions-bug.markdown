﻿---
layout: post
title: "F# sequence expressions bug"
date: 2010-10-08 10:58:23
categories: 1267960448
tags: fsharp seq ienumerable dispose finally
---
Нашёл занятный баг в F# 2.0:

{% highlight fsharp %}
let xs = seq {
    try yield 1
        yield! seq {
           try yield 2
               yield! seq {
                 try yield 3
                 finally printfn "dispose::3"
               }
           finally printfn "dispose::2"
                   failwith "bar!" // <---
        }
    finally printfn "dispose::1"
  }

for _ in xs do ()

{% endhighlight %}

Данный конечно же с грохотом падает, но интерес представляет то, какие блоки finally выполняются. Не смотря на то, что во втором по вложенности finally происходит исключение, внешние блоки finally тоже должны отработать, однако реальный вывод данного кода таков:

<blockquote>
<pre class="box">dispose::3
dispose::2

{% endhighlight %}

</blockquote>
Это связано с тем, что `yeild!` реально использует стек из `IEnumerator<T>`, для того чтобы снизить стоимость перебора `IEnumerable<T>` на вложенных последовательностях. Соответсвенно, при возникновении исключения во время перебора, сгенерированный F# код должен последовательно доставать из стека энумераторы и делать каждому `Dispose()`. К сожалению, код не рассчитан на то, что во время `Dispose()` тоже может произойти исключение, однако оставшиеся `Dispose()` всё равно следут вызвать.