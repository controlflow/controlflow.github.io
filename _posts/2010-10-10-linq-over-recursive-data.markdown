---
layout: post
title: "LINQ over recursive data"
date: 2010-10-10 02:33:00
author: Aleksandr Shvedov
tags: csharp ienumerable rec linq
---
I've needed to traverse a tree and flatten it into a sequence on several occasions. A recursive iterator worked well enough, but I couldn't find a reusable operation for this in either LINQ or Reactive Extensions for .NET.

There is also a performance concern: with nested C# iterators, the cost of producing each element can grow linearly with the depth of the structure, because each element passes through a chain of `IEnumerator<T>` wrappers. One way to avoid this is to keep the active enumerators in a singly linked list, with the current enumerator directly accessible at the head. This replaces the chain of nested iterator calls with explicit state allocated on the heap.

The following code generalizes tree traversal into a set of `SelectRec()` methods:

```c#
using System;
using System.Collections.Generic;

public static class RecExtensions
{
  // Public API

  public static IEnumerable<T> SelectRec<T>(
    this IEnumerable<T> source, Func<T, IEnumerable<T>> selector)
  {
    return SelectRec(source, _ => true, selector);
  }

  public static IEnumerable<T> SelectRec<T>(
    this IEnumerable<T> source, Func<T, bool> predicate, Func<T, IEnumerable<T>> selector)
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
    T source, Func<T, bool> predicate, Func<T, IEnumerable<T>> selector)
  {
    return SelectRec(new[] { source }, predicate, selector);
  }

  // Implementation

  static IEnumerable<T> SelectRecImpl<T>(
    IEnumerable<T> source, Func<T, bool> predicate, Func<T, IEnumerable<T>> selector)
  {
    EnumList<T> list = null;
    try
    {
      IEnumerator<T> e = null;
      while (true)
      {
        // Obtain a new enumerator when needed.
        if (e == null)
          e = source.GetEnumerator();

        try
        {
          // Advance the current enumerator.
          while (e.MoveNext())
          {
            var o = e.Current;
            yield return o;

            // Descend into the child sequence when requested.
            if (predicate(o))
            {
              source = selector(o);

              // Suspend the current enumerator until the children are processed.
              list = new EnumList<T>(e, list);
              e = null;

              break;
            }
          }
        }
        finally
        {
          // Dispose the current enumerator unless it has been suspended.
          if (e != null)
            e.Dispose();
        }

        if (e == null)
          continue; // Start enumerating the child sequence.
        if (list == null)
          break; // No suspended enumerators remain.
        else
        {
          e = list.Enumerator;
          list = list.Next;
        }
      }
    }
    finally
    {
      // Dispose all suspended enumerators, even if disposing
      // the current enumerator threw an exception.
      DisposeRec(list);
    }
  }

  // Dispose the enumerator stack in order, ensuring that an exception
  // from one enumerator does not prevent disposal of the others.
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

  // Immutable singly linked list.
  sealed class EnumList<T>
  {
    public readonly IEnumerator<T> Enumerator;
    public readonly EnumList<T> Next;

    public EnumList(IEnumerator<T> enumerator, EnumList<T> next)
    {
      this.Enumerator = enumerator;
      this.Next = next;
    }
  }
}
```

Maintaining a list of `IEnumerator<T>` instances introduces another concern: they must all be disposed correctly if enumeration throws. In this implementation, the recursive `DisposeRec()` method places each call to `Dispose()` inside a `try`/`finally` block. This ensures that an exception from one enumerator's `Dispose()` does not prevent the remaining outer enumerators from being disposed.

The public API consists of two pairs of methods: one pair accepts a single root value, and the other accepts a sequence of roots. Each pair includes an overload with a predicate that determines whether to descend into a value's child sequence. The other overload treats every value as a potential parent. The predicate controls traversal, not whether the value itself appears in the result. All overloads require a selector that returns the child sequence. For example, the following query traverses the directories on all available drives:

```c#
var dirs = DriveInfo
  .GetDrives()
  .Where(d => d.IsReady)
  .Select(d => d.RootDirectory)
  .SelectRec(dir =>
  {
    try
    {
      return dir.EnumerateDirectories();
    }
    catch (UnauthorizedAccessException)
    {
      // easiest way to handle access errors
    }

    return Enumerable.Empty<DirectoryInfo>();
  });
```

The usefulness of this API depends on the traversal requirements. A predicate and a child-sequence selector may be sufficient for simple cases, but more complex traversal rules would require a richer interface.

The implementation could also be extended into a `SelectDistinctRec()` method for traversing object graphs with shared references or cycles. A `HashSet<T>` could track values already visited, preventing repeated traversal and allowing a finite graph with cycles to be flattened into a finite sequence.