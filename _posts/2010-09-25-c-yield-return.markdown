---
layout: post
title: "C# yield return"
date: 2010-09-25 17:52:00
categories: 1185163082
tags: csharp enumerable iterator yield return
---
До недавнего времени совсем не знал, что методы-итераторы в C# (ещё с версии 2.0) могут возвращать типы, отличные от <b>IEnumerable<T></b>:

{% highlight C# %}

using System.Collections;
using System.Collections.Generic;

class Foo
{
	IEnumerable Bar1() { yield return 1; }
	IEnumerator Bar2() { yield return 2; }
	IEnumerable<int> Bar3() { yield return 3; }
	IEnumerator<int> Bar4() { yield return 4; }

	static void Main() { }
}

{% endhighlight %}

Логично было бы полагать, что именно IEnumerator’ы можно возвращать для удобной реализации <b>IEnumerable<T></b> своими типами, а я что-то совсем не догадывался… :(

<blockquote>
<b>10.14.2 Enumerable interfaces</b>
The enumerable interfaces are the non-generic interface System.Collections.IEnumerable and all instantiations of the generic interface System.Collections.Generic.IEnumerable<T>. For the sake of brevity, in this chapter these interfaces are referenced as IEnumerable and IEnumerable<T>, respectively.

</blockquote>
Кстати, такой итератор:

{% highlight C# %}

IEnumerable Bar1() { yield return 1; }

{% endhighlight %}

…на самом то деле возвращает значение типа <b>IEnumerable<object></b>, но это нигде в спеке не документировано и полагаться на это, конечно же, не стоит… :)