---
layout: post
title: "ISerializationSurrogate interface"
date: 2010-10-20 01:13:00
author: Aleksandr Shvedov
tags: csharp serialization surrogate yield
---
I needed to serialize a C# iterator. The obstacle is that the C# compiler does not mark its generated iterator classes with `[Serializable]`. The same applies to the closure classes generated for lambdas and anonymous methods. The corresponding F# types do not have this restriction:

```fsharp
let xs = seq { yield 1 }
xs.GetType().IsSerializable // true

id.GetType().IsSerializable // true
```

One way to handle this is to use a serialization surrogate, which supplies the serialization and deserialization logic for a type that does not provide it itself. A simple implementation uses reflection to enumerate the object's fields and store their values in `SerializationInfo`. Since the compiler-generated iterator type cannot be referenced directly in source code, reflection provides a way to inspect its state:

```c#
using System;
using System.Reflection;
using System.Runtime.Serialization;

sealed class AnySurrogate : ISerializationSurrogate
{
  private const BindingFlags AllFields =
    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

  public void GetObjectData(object obj, SerializationInfo info, StreamingContext context)
  {
    Type objType = obj.GetType();
    foreach (var field in objType.GetFields(AllFields))
    {
      info.AddValue(field.Name, field.GetValue(obj), field.FieldType);
    }
  }

  public object SetObjectData(
    object obj,
    SerializationInfo info,
    StreamingContext context,
    ISurrogateSelector selector)
  {
    Type objType = obj.GetType();
    foreach (var serializedValue in info)
    {
      var field = objType.GetField(serializedValue.Name, AllFields);
      if (field == null)
      {
        throw new SerializationException(string.Format(
          "Field '{0}' was not found in the target type.", serializedValue.Name));
      }

      if (field.FieldType != serializedValue.ObjectType)
      {
        throw new SerializationException(string.Format(
          "Serialized field '{0}' has type '{1}', but the target field has type '{2}'.",
          serializedValue.Name, serializedValue.ObjectType, field.FieldType));
      }

      field.SetValue(obj, serializedValue.Value);
    }

    return obj;
  }
}
```

Here is an example of using the surrogate:

```c#
using System;
using System.Collections;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Formatters.Binary;

class Foo
{
  private static IEnumerator Bar()
  {
    var now = DateTime.Now;

    yield return now.Ticks;
    yield return now.Ticks;
  }

  private static void Main()
  {
    var e1 = Bar();

    // create a surrogate selector
    var selector = new SurrogateSelector();

    selector.AddSurrogate(
      type: e1.GetType(), // the compiler-generated iterator type
      context: new StreamingContext(
        StreamingContextStates.All), // include all serialization contexts
      surrogate: new AnySurrogate() // the surrogate instance
    );

    using (var mem = new MemoryStream())
    {
      var binary = new BinaryFormatter
      {
        SurrogateSelector = selector
      };

      e1.MoveNext(); // first yield return
      Console.WriteLine(e1.Current);

      // serialize the iterator instance
      binary.Serialize(mem, e1);
      mem.Position = 0;

      // deserialize the iterator instance
      var e2 = (IEnumerator)binary.Deserialize(mem);

      e2.MoveNext(); // second yield return
      Console.WriteLine(e2.Current);
      Console.WriteLine(e2.MoveNext()); // false
    }
  }
}
```

A custom implementation of `ISurrogateSelector` could select a surrogate automatically, removing the need to register each concrete type explicitly. This would extend the approach to other types that are not marked with `[Serializable]`.