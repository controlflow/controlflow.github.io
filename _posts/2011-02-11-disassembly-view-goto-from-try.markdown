---
layout: post
title: "Disassembly view и goto from try { }"
date: 2011-02-11 17:43:00
tags: asm assembly visualstudio debugging try finally goto
---
Вот мне всегда было интересно как имплементится на машинном уровне поведение такого кода:

```c#
class Foo {
  static void Main() {
    bool jump = true;

    Label:
    try {
      System.Console.WriteLine("try");
      if (jump) {
        jump = false;
        goto Label;
      }
    } finally {
      System.Console.WriteLine("finally");
    }
  }
}
```

Который выводит на экран:

    try
    finally
    try
    finally

То есть любой выход из блока `try`, даже прыжком “вверх” по коду, должен завершаться вызовом блока `finally`. Я с ассемблером не дружу, но оказалось всё очень просто:

```c#
     4:     static void Main() {
...
     5:         bool jump = true;
00000039  mov         eax,1 
0000003e  and         eax,0FFh 
00000043  mov         dword ptr [ebp-24h],eax 
00000046  nop 
     6: 
     7:         Label:
     8:         try {
00000047  nop 
     9:             System.Console.WriteLine("try");
00000048  mov         ecx,dword ptr ds:[02C32030h] 
0000004e  call        641F703C 
00000053  nop                   // в зависимости от условия
    10:             if (jump) { // к выходу из try-блока
00000054  cmp         dword ptr [ebp-24h],0
00000058  sete        al                     
0000005b  movzx       eax,al                 
0000005e  mov         dword ptr [ebp-28h],eax
00000061  cmp         dword ptr [ebp-28h],0 
00000065  jne         00000083 
00000067  nop 
    11:                 jump = false;
00000068  xor         edx,edx 
0000006a  mov         dword ptr [ebp-24h],edx 
    12:                 goto Label;
0000006d  nop 
0000006e  mov         dword ptr [ebp-1Ch],0     // сохраняем
00000075  mov         dword ptr [ebp-18h],0FCh  // в стек
0000007c  push        3C012Dh // <== адрес перехода @ 00000047
00000081  jmp         0000009A 
    13:             }
    14:         }
00000083  nop 
00000084  nop 
00000085  mov         dword ptr [ebp-1Ch],0 
0000008c  mov         dword ptr [ebp-18h],0FCh // или
00000093  push        3C0136h  // <== адрес перехода @ 000000ac
00000098  jmp         0000009A 
    15:         finally {
0000009a  nop 
    16:             System.Console.WriteLine("finally");
0000009b  mov         ecx,dword ptr ds:[02C32034h] 
000000a1  call        641F703C 
000000a6  nop 
    17:         } 
000000a7  nop              // после finally каждый раз
000000a8  pop         eax  // достаём адрес из стека
000000a9  jmp         eax  // и прыгаем по нему
000000ab  nop 
    18: 
    19:         Debugger.Break();
000000ac  call        64700020 
000000b1  nop  
    20:     }
... 
```

То есть найдя прыжок из `try`-блока, JIT-компилятор сгенерировал после `finally`-блока прыжок по адресу из вершины стека и убедился, что при любом из выходов из `try` в стек положат адрес кода, с которого следует продолжать исполнение. Аналогичная магия происходит при использовании `break`, `continue` и `return` внутри `try { }`.

Возникает вопрос: как посмотреть достоверный disassembly управляемого кода? Очень просто - включаем в студии *address-level debugging*:

![]({{ site.baseurl }}/images/clr-disassembly.png)

Вставляем в код вызов `System.Diagnostics.Debugger.Break()`, собираем проект в *RELEASE*. Если вам надо видеть *соответствие *C#-исходников с соответствующими машинными инструкциями, то надо компилировать с отключенными оптимизациями (это оптимизации на MSIL-уровне, они относительно не сильно видоизменяют машинный код):

![]({{ site.baseurl }}/images/clr-disassembly2.png)

Включая оптимизации C#, вы получите *достоверный* ассемблерный листинг, но что там есть что - вам придётся разбираться самому. В любом случае необходимо включить компиляцию с полной debug-информацией:

![]({{ site.baseurl }}/images/clr-disassembly3.png)

После этого запускаем код без отладчика (это задействует оптимизации на уровне JIT):

![]({{ site.baseurl }}/images/clr-disassembly4.png)

Дожидаемся срабатывания `Debugger.Break()` и вызываем отладчик:

![]({{ site.baseurl }}/images/clr-disassembly5.png)

Подключаемся нужным экземпляром Visual Studio и вызываем из контекстного меню *Go to disassembly* - вот и всё, можно смело курить ассмеблерные листинги. Однако следует обратить внимание вот ещё на что:

* Некоторые вызовы могут быть попросту не скомпилированы JIT’ом. Следует организовывать код так, чтобы исследуемый фрагмент хотя раз бы выполнился, а уже потом подключаться отладчиком. Либо можно воспользоваться статическим методом `PrepareMethod` класса `System.Runtime.CompilerServices.RuntimeHelpers` для того, чтобы вручную вызвать JIT-компиляцию заданных методов.
* Иногда исследуемый код подвергается inline-оптимизации и это может мешать. Запретить инлайнинг того или иного метода можно с помощью атрибута `MethodImplAttribute`из того же пространства имён:
```c#
using System.Runtime.CompilerServices;

class Foo {
  [MethodImpl(MethodImplOptions.NoInlining)]
  public static void NoInline() { }
}
```