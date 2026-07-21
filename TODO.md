1) Fix Void level, currently the difficulty level is impossible there

**Responsible: Sasha**

2) Implement the panic scale. The panic increases x (~5) times faster than decreases

**Responsible: Andrey**. TODO: implement the panic scale. Increases when looking at the trigger object (implement some of the trigger object for unit testing), and make it decrease in a calm environment. Implement the logic when the player finds some particular objects (like the candy) that decrease the panic. UPD: the basic function is done, need to review and maybe improve the minor things related to it

3) Think about the ways to remove the panic besides just waiting until it gets back to the normal condition

4) Think about random noises / half-screamers at the random moments in the game to keep the tension. Examples: floor crack, painting falls. TODO: create sounds, textures, falling logic in case of paintings. UPD: some sounds are already there, check the repo. Important thing is some new textures and 3D models, the logic of the falling objects

**Responsible: Spartak**

5) Think about the audio text that the player will hear and make it through TTS. Leave notes but add some audio features

**Responsible: Spartak**

7) Think about the checkpoints - the game starts from the beginning / or at the beginning of the level / several levels back

8) Somewhere at the end of the game we can create a maze on the wall - the player needs to use the mouse to pass the maze somehow (think about the logic)

### How we identify that the player is triggered / panicking / it is the time to fail the game

1) The user goes into the dark place to collect a key (or another object). The longer the player stays in the dark - the higher is the panic on the panic scale. Once the user escapes the dark the panic decreases. If the panic reaches a certain level - the user dies

2) There is a 3D model of a monster. At the random moment it starts running towards the player. If the player runs away / stops watching at the creature - it means the player is panicking and fails the game. If the player stares at the creature for say 5 seconds without running away / stopping staring at it - it means the player passed the test and the creature disappears. No panic scale included, the player dies immediately after failing

Reference: asylum patient, leather mask on (like the leatherface), straitjacket on. Take Outlast as the reference 

**Responsible: Danil**. TODO: generate 3D model of the monster from the reference. Make the monster appear at the random moment of the entire game. If stare for 5 seconds, the monster disappers. If runs away / stares somewhere else - the player fails and the screamer appears

4) There are some trigger objects (weird paintings / knife / blood on the floor). The difference between the creature from 2) is that the player MUST NOT stare at these objects. The panic scale increases - the longer the players stares at them.

5) You hear a sound telling to not turn back / you hear the somebody is breathing just behind you - and the goal is not to turn back

Два результата на выходе:

+ Тех репорты на архиве (могу вписать сколько угодно авторов) и на хабре (там автором буду я, но я могу каким-то образом упоминать других разрабов)

+ Игра будет выложена бесплатно в Steam (под статусом демо), Yandex Games, ...

В последней версии игры есть монстр (главный монстр), он появляется рандомно на уровнях

Борис - фиксить 2Д монстра

+ Точно появляется в лаборатории (первый уровень), вроде бы появляется в доме (второй уровень, не уверен)
+ Он не появляется на остальных уровнях (хз почему) - коридоре, закулисье, пустота. Кажется, что в коридоре и пустоте он не нужен (в пустоте есть свой монстр), а в закулисье нужно добавить. TODO: добавить везде где надо
+ Реализовать механику перемещения монстра (хотя бы 2д картинки)
+ Суть в том, что от него нельзя отворачиваться, если отворачиваешься - ты проигрываешь. Если смотришь на него - он исчезает. Также от него нельзя убегать. Если убегаешь - ты проигрываешь. Мб сделать это через резкий рост паники - то есть игрок проигрывает не мгновенно. Реализовать нормально эту механику
+ Попробовать сделать 3D-модель через text-to-3d
+ 3D модели будут сразу засунуты в Godot

На последнем уровне (пустота) монстр - это именно враг, и нужно не дать ему себя убить (надо подумать, как это сделать через игровую механику). Идея: в какой-то момент игры паника не сбрасывается просто так. Она и растет и падает от определенных действий. Чем выше паника - тем быстрее и активнее монстр. Идея уровня - нужно снизить панику до нуля за счет правильных действий, монстр исчезнет, и откроется дверь в новый уровень. Если паника низкая - монстр двигается очень медленно, если паника высокая - монстр двигается быстро и агрессивно. На последнем уровне паника работает НЕ как на остальных - игрок заходит на уровень и у него сразу какой-то уровень паники. На всех других уровнях паника работает по старой механике. Чтобы выиграть уровень - нужно убрать панику в ноль. Нужно выполнить задания. Примеры: включить освещение, итд нужно погуглить

Андрей:

1) Сделать новую логику паники чисто для уровня пустота (чел заходит условно с 30%, монстр уже активен). Паника сама по себе понижаться не может, только по триггерам
2) Придумать (посмотреть референсы / спросить клод), какие задания должен выполнять игрок чтобы понижать панику
3) Продумать сценарии как снизить панику до нуля чтобы выиграть уровень
4) Адаптировать самого монстра (идет за игроком, меняется скорость, итд)




