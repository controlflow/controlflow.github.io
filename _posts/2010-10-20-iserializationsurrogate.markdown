---
layout: post
title: "ISerializationSurrogate"
date: 2010-10-20 01:13:00
tags: csharp serialization surrogate yield
---
Тяжёлая жизнь довела меня до того, что мне потребовалось сериализовать итераторы C#. Проблема в том, что компилятор C# не считает должным вешать атрибут `[Serializable]` на генерируемые для итераторов классы (а так же на классы-замыкания для лямбда-выражений и анонимных методов). В F# подобной проблемы не существует:

```fsharp
let xs = seq { yield 1 } in xs.GetType().IsSerializable // true
id.GetType().IsSerializable // true
```

Один из вариантов решения проблемы - использовать объект-суррогат, подменяющий несериализуемый объект и описывающий корректный процесс сериализации / десериализации объекта. Самая простая реализация - проход рефлексией по полям объекта и сохранение их в объект `SerializationInfo` (вообщем-то нам ничего другого и не остаётся сделать, так как реальный тип итератора недоступен). Пример реализации:

```c#
using System;
using System.Reflection;
using System.Runtime.Serialization;

sealed class AnySurrogate : ISerializationSurrogate
{
  const BindingFlags AllFields =
    BindingFlags.Instance | BindingFlags.Public | BindingFlags.NonPublic;

  public void GetObjectData(object obj, SerializationInfo info, StreamingContext context) {
    Type objType = obj.GetType();
    foreach (var field in objType.GetFields(AllFields)) {
      info.AddValue(
        field.Name,
        field.GetValue(obj),
        field.FieldType);
    }
  }

  public object SetObjectData(object obj, SerializationInfo info, StreamingContext context, ISurrogateSelector selector) {
    Type objType = obj.GetType();
    foreach (var serializedValue in info) {
      var field = objType.GetField(serializedValue.Name, AllFields);
      if (field == null) {
        throw new SerializationException(string.Format(
          "Field '{0}' is not founded in target type.", serializedValue.Name));
      }

      if (field.FieldType != serializedValue.ObjectType) {
        throw new SerializationException(string.Format(
          "Field '{0}' with type '{1}' is not matched with the target field type of '{2}'.",
          serializedValue.Name, serializedValue.ObjectType, field.FieldType));
      }

      field.SetValue(obj, serializedValue.Value);
    }

    return obj;
  }
}
```

Пример использования:

```c#
using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.Serialization;
using System.Runtime.Serialization.Formatters.Binary;

class Foo {
  static IEnumerator Bar() {
    var now = DateTime.Now;

    yield return now.Ticks;
    yield return now.Ticks;
  }

  static void Main() {
    var e1 = Bar();

    // создаём экземпляр итератора
    var selector = new SurrogateSelector();

    selector.AddSurrogate(
      type: e1.GetType(), // реальный тип итератора
      context: new StreamingContext(
        StreamingContextStates.All), // это важно!
      surrogate: new AnySurrogate() // экземпляр суррогата
    );

    using (var mem = new MemoryStream()) {
      var binary = new BinaryFormatter {
        SurrogateSelector = selector
      };

      e1.MoveNext(); // первый yield return
      Console.WriteLine(e1.Current);

      // сериализуем экземпляр итератора
      binary.Serialize(mem, e1);
      mem.Position = 0;

      // десериализуем экземпляр итератора
      var e2 = (IEnumerator)binary.Deserialize(mem);

      e2.MoveNext(); // второй yield return
      Console.WriteLine(e2.Current);
      Console.WriteLine(e2.MoveNext()); // false
    }
  }
}
```

Похоже на то, что реализовав `ISurrogateSelector`, можно избавиться от необходимости в задании типа объекта при добавлении объекта-суррогата и сериализовать что угодно, не отмеченное `[Serializable]`, но это уже другая история…