# Share conflict, can't delete or create public share

**URL:** https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112
**Category:** zrok
**Created:** [September 23, 2026, 9:34am UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112 "2026-09-23T09:34:24Z")
**Posts on this page:** 9
**Page:** 1

<div class="post-metadata">

### Author: ![W4ldschr31n](https://avatars.discourse-cdn.com/v4/letter/w/d78d45/32.png) [@W4ldschr31n](https://openziti.discourse.group/u/W4ldschr31n)
#### Post date: [September 23, 2026, 9:34am UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/1 "2026-09-23T09:34:24Z")

</div>

Hi, I was using my public share yesterday when my internet connection crashed. It seems the url share is now locked but I can't delete it.\
When I try to share public I get: [ERROR]: unable to create share (unable to create share: [POST /share][409] shareConflict "name [REDACTED] in namespace 'public' is already in use by another share")\
When I go to the url I get: share `1rbv4b9xqaxi` not found! are you running `zrok2 share` for this share?\
When I try to delete `1rbv4b9xqaxi` I get: ERROR main.(\*deleteShareCommand).run [DELETE /unshare][404] unshareNotFound

---

<div class="post-metadata">

### Author: ![Saxan007](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/saxan007/32/4350_2.png) [@Saxan007](https://openziti.discourse.group/u/Saxan007)
#### Post date: [September 23, 2026, 9:40am UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/2 "2026-09-23T09:40:34Z")

</div>

I have the same problem. But no one has answered or offered any advice for over two days now.

---

<div class="post-metadata">

### Author: ![Kurokatana94](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/kurokatana94/32/4348_2.png) [@Kurokatana94](https://openziti.discourse.group/u/Kurokatana94)
#### Post date: [September 23, 2026, 9:56am UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/3 "2026-09-23T09:56:23Z")

</div>

Staff replied here: [Stuck zrok2 account – enable and web console release both return 500 error - #7 by smilindave26](https://openziti.discourse.group/t/stuck-zrok2-account-enable-and-web-console-release-both-return-500-error/6041/7)\
It seems they know about the issue and currently working on it

---

<div class="post-metadata">

### Author: ![Saxan007](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/saxan007/32/4350_2.png) [@Saxan007](https://openziti.discourse.group/u/Saxan007)
#### Post date: [September 23, 2026, 10:26am UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/4 "2026-09-23T10:26:51Z")

</div>

> [@Kurokatana94](#):
>
> Staff replied here: [Stuck zrok2 account – enable and web console release both return 500 error - #7 by smilindave26](https://openziti.discourse.group/t/stuck-zrok2-account-enable-and-web-console-release-both-return-500-error/6041/7)\
> It seems they know about the issue and currently working on it

But they replied and resolved the matter privately in that case. Meanwhile, I haven't been able to get an answer for three days now!

---

<div class="post-metadata">

### Author: ![Kurokatana94](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/kurokatana94/32/4348_2.png) [@Kurokatana94](https://openziti.discourse.group/u/Kurokatana94)
#### Post date: [September 23, 2026, 10:35am UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/5 "2026-09-23T10:35:06Z")

</div>

No it wasn't private, they're trying to resolve the issue for everyone. I have the same problem and it's ongoing, just need to wait 'till it's fixed

---

<div class="post-metadata">

### Author: ![smilindave26](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/smilindave26/32/185_2.png) [@smilindave26](https://openziti.discourse.group/u/smilindave26)
#### Post date: [September 23, 2026, 2:51pm UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/6 "2026-09-23T14:51:40Z")

</div>

yes. we're working on it. A handful of intertwined issues related to our rate limiters, account cleanup, and conflicts that arise from mixing zrok and zrok2 environments. We can address some of these manually, case by case, until a solution is in place (a team is assigned to that), a software update we're working on, and a likelihood that we'll end support for `zrok` and require use of `zrok2`. We will post here as updates are made.

---

<div class="post-metadata">

### Author: ![Saxan007](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/saxan007/32/4350_2.png) [@Saxan007](https://openziti.discourse.group/u/Saxan007)
#### Post date: [September 24, 2026, 6:07am UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/7 "2026-09-24T06:07:57Z")

</div>

How do I delete stuck, corrupted environments? They keep throwing a 500 error and cannot be deleted. I haven't been able to remove them even after three days.

---

<div class="post-metadata">

### Author: ![mguthrie88](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/mguthrie88/32/151_2.png) [@mguthrie88](https://openziti.discourse.group/u/mguthrie88)
#### Post date: [September 24, 2026, 12:56pm UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/8 "2026-09-24T12:56:43Z")

</div>

Hi @Saxan007 - I've responded to your issue in another thread

---

<div class="post-metadata">

### Author: ![Saxan007](https://yyz2.discourse-cdn.com/free1/user_avatar/openziti.discourse.group/saxan007/32/4350_2.png) [@Saxan007](https://openziti.discourse.group/u/Saxan007)
#### Post date: [September 24, 2026, 1:44pm UTC](https://openziti.discourse.group/t/share-conflict-cant-delete-or-create-public-share/6112/9 "2026-09-24T13:44:32Z")

</div>

I saw it; thanks for the help. I waited quite a while.
