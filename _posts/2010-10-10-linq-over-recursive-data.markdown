---
layout: post
title: "LINQ over recursive data"
date: 2010-10-10 02:33:00
categories: 1279189540
tags: csharp ienumerable rec linq
---
Пару раз сталкивался с такой простой задачей, как проход по древовидной структуре данных и выравнивание её в плоскую последовательность… Решал я это дело рекурсивным итератором и результат меня вполне устраивал, но по пути до меня дошло, что ни в LINQ, ни в Reactive Extensions for .NET нет подобного алгоритма, поддающегося переиспользованию.

Так же существует проблема линейного увеличения алгоритмической сложности перебора последовательности при увеличении глубины структуры - вложенные итераторы C# вполне могут “притормаживать” на глубоких структурах из-за кучи декораторов `IEnumerator<T>`. Эту проблему можно решить, складывая энумераторы всех вложенных последовательностей в однонаправленный список так, чтобы текущий энумератор всегда находился в голове списка, тогда до него всегда будет рукой подать и нагрузка на стек заменится нагрузкой на кучу.

Код ниже - попытка обобщить обход древовидных структур в набор методов-расширений `SelectRec()`:

{% highlight C# %}
using System;

using System.Collections.Generic;

public static class RecExtensions
{
	#region Public surface

	public static IEnumerable<T> SelectRec<T>(
		this IEnumerable<T> source,
		Func<T, IEnumerable<T>> selector)
	{
		return SelectRec(source, _ => true, selector);
	}

	public static IEnumerable<T> SelectRec<T>(
		this IEnumerable<T> source,
		Func<T, bool> predicate,
		Func<T, IEnumerable<T>> selector)
	{
		if (source == null)
			throw new ArgumentNullException("source");
		if (predicate == null)
			throw new ArgumentNullException("predicate");
		if (selector == null)
			throw new ArgumentNullException("selector");

		return SelectRecImpl(source, predicate, selector);
	}

	public static IEnumerable<T> SelectRec<T>(
		T source, Func<T, IEnumerable<T>> selector)
	{
		return SelectRec(new[] { source }, _ => true, selector);
	}

	public static IEnumerable<T> SelectRec<T>(
		T source, Func<T, bool> predicate,
		Func<T, IEnumerable<T>> selector)
	{
		return SelectRec(new[] { source }, predicate, selector);
	}

	#endregion
	#region Implementation

	static IEnumerable<T> SelectRecImpl<T>(
		IEnumerable<T> source,
		Func<T, bool> predicate,
		Func<T, IEnumerable<T>> selector)
	{
		EnumList<T> list = null;
		try
		{
			IEnumerator<T> e = null;
			while (true)
			{
				// get the new enumerator if needed
				if (e == null) e = source.GetEnumerator();
				try
				{
					// iterate over the current enumerator
					while (e.MoveNext())
					{
						var o = e.Current;
						yield return o;

						// if current - is inner enumerable
						if (predicate(o))
						{
							// get the new enumerable
							source = selector(o); 
							// store current
							list = new EnumList<T>(e, list);
							e = null;

							break; // delay enumerator
						}
					}
				}
				finally // dispose the enumerator if not delayed
				{
					if (e != null) e.Dispose();
				}

				if (e == null) continue; // inner enumerable
				if (list == null) break; // nothing to enumerate
				else
				{
					e = list.Enumerator;
					list = list.Next;
				}
			}
		}
		finally
		{
			// enumerator 'e' here is already disposed,
			// but exception may be thrown during dispose
			// so we should dispose all the enumerator list
			DisposeRec(list);
		}
	}

	/// <summary>
	/// Recursively disposes the elements of enumerator stack
	/// in correct order with the correct exception handling.
	/// </summary>
	static void DisposeRec<T>(EnumList<T> xs)
	{
		if (xs != null)
		{
			IDisposable disposable = xs.Enumerator;
			try
			{
				disposable.Dispose();
			}
			finally
			{
				DisposeRec(xs.Next);
			}
		}
	}

	/// <summary>
	/// Immutable single-linked list.
	/// </summary>
	sealed class EnumList<T>
	{
		public readonly IEnumerator<T> Enumerator;
		public readonly EnumList<T> Next;

		public EnumList(
			IEnumerator<T> enumerator, EnumList<T> next)
		{
			this.Enumerator = enumerator;
			this.Next = next;
		}
	}

	#endregion
}

{% endhighlight %}

Следует заметить, что при использовании списка `IEnumerator<T>` возникает другая проблема - правильно делать им `Dispose()` в случаях, когда во время перебора последовательности возникает исключение. В коде выше это решено в рекурсивном методе `DisposeRec()`, который за счёт рекурсии формирует вызовы `Dispose()` всех итераторов во множестве try-finally блоков. Это нужно чтобы возможное исключение во время `Dispose()` одного из энумераторов не повлияло на вызов `Dispose()` внешних энумераторов.

В public surface торчит две пары методов, два из них принимают на вход единственное значение, два других - последовательности. В каждой паре одна перегрузка предусматривает параметр-предикат, вычисляющий какие значения содержат в себе подпоследовательности, а другая перегрузка считает все значения потенциально содержащими подпоследовательности. В любом случае надо указать функцию-селектор подпоследовательности. Всё просто, теперь можно пробежаться по всем папкам всех дисков:

{% highlight C# %}
var dirs = DriveInfo
	.GetDrives()
	.Where(d => d.IsReady)
	.Select(d => d.RootDirectory)
	.SelectRec(dir => {
		try { return dir.EnumerateDirectories(); }
		catch (UnauthorizedAccessException) { }
		return Enumerable.Empty<DirectoryInfo>();
	});

{% endhighlight %}

Не обращайте внимание на catch, это самый быстрый способ проверить есть ли у приложения права на тот или иной каталог Windows, гыгы :)

Не знаю, удобно ли будет им пользоваться в реальных ситуациях, скорее всего задание правила выборки предикатом-фильтром и функцией-селектором достаточно совсем для небольшого количества сценариев.

Очень легко этот код можно доработать чтобы получить что-то вроде `SelectDistinctRec()`, который может пригодиться если, например, если у Вас есть объекты и сложными связями между ними, включая циклические, и Вам следует получить конечную последовательность всех объектов, связанных с данным. Использование `HashSet<T>` позволит корректно обрабатывать циклы, отбрасывая уже найденные объекты.

Короче вот такая фигня :)