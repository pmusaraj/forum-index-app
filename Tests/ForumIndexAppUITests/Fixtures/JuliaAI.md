# How to start using AI?

**URL:** <https://discourse.julialang.org/t/how-to-start-using-ai/139973>\
**Category:** Offtopic\
**Tags:** ai\
**Created:** [October 12, 2026, 3:14pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973 "2026-10-12T15:14:53Z")\
**Posts on this page:** 20\
**Page:** 1

<div class="post-metadata">

**Author:** ![Nathan\_Boyer](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/nathan_boyer/32/14825_2.png) [@Nathan\_Boyer](https://discourse.julialang.org/u/Nathan_Boyer)\
**Post date:** [October 12, 2026, 3:14pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/1 "2026-10-12T15:14:53Z")

</div>

I’m looking for guidance on how to start using AI for Julia coding and in general.

So far, my AI experience is asking questions in new Google search tabs. I tried searching for articles and videos on how to get started, but they all feel like ads. The projects I’ve seen announced to “make it easy” to use AI with Julia (e.g. SpaceStation, Kaimon, BonitoBook, AIHelpMe) have differing setup instructions that I don’t understand, requiring some combination of servers, secrets, keys, configs, gates, JSON files, prepaid credits …

Can someone recommend a simple and preferably free way to dip my toe in?

---

<div class="post-metadata">

**Author:** ![cshen](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/cshen/32/217287_2.png) [@cshen](https://discourse.julialang.org/u/cshen)\
**Post date:** [October 12, 2026, 4:08pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/2 "2026-10-12T16:08:49Z")

</div>

The most basic setup I can think of (but that can take you much further that you might think) is an harness like `pi` (there are many others, but this one is very minimal) and a provider. Then you connect the harness to the provider via an API key or a simple login and you’re good to go.

Regarding the “Free” part it’s harder. If you have the hardware you can run models locally (small ones don’t need a lot of memory), but that is more of a “head dive” rather than “dipping the toes”. Otherwise, you can go either subscription or consume based where you top up an amount.

I personally am liking a lot the `opencode-go` subscription, which is 10eur with decent limits and decent model selection. Sometimes you can find models that are listed as free, but it goes without saying that the payment in that case is the data you provide for training (also usually heavily throttled).

Overall in terms of providers, you can go directly to the mothership: `OpenAI`, `Anthropic`,`Z.AI`,`Deepseek`,etc.. or go for “aggregators”, like `opencode-go` or `openrouter`.  
The tradeoff is, more model selection, but usually not as cheap as if going directly to the tap.

There are many providers that also offer various levels of data retention policies and or training, especially when talking about open weight models.

---

<div class="post-metadata">

**Author:** ![Eben60](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/eben60/32/13475_2.png) [@Eben60](https://discourse.julialang.org/u/Eben60)\
**Post date:** [October 12, 2026, 4:35pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/3 "2026-10-12T16:35:01Z")

</div>

Which environment you otherwise are using for coding?

---

<div class="post-metadata">

**Author:** ![Nathan\_Boyer](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/nathan_boyer/32/14825_2.png) [@Nathan\_Boyer](https://discourse.julialang.org/u/Nathan_Boyer)\
**Post date:** [October 12, 2026, 5:01pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/4 "2026-10-12T17:01:15Z")

</div>

Visual Studio Code and Pluto.

---

<div class="post-metadata">

**Author:** ![Eben60](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/eben60/32/13475_2.png) [@Eben60](https://discourse.julialang.org/u/Eben60)\
**Post date:** [October 12, 2026, 5:30pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/5 "2026-10-12T17:30:29Z")

</div>

I have zero experience with notebooks, but I can share how I use VS Code for programming as well as writing boring documents. I do a bit of hobby coding, and a bit for work, but it is not 5 days 8 hours a week.

I have a Google One AI Premium subscription, costing about 20€$. With that, I use Gemini heavily for all kinds of questions, privately and professionally. Up to six family members can be included under one plan, BTW. In VS Code, I installed the Google Antigravity extension. For the price, it provides relatively generous access to Gemini agents, and a bit of Claude, which is definitely more intelligent. Next, I installed Kaimon according to the setup instructions.

Once configured, you can open your workspace and start AI-assisted coding. For configuration questions, either the built-in Gemini agent or the web version can assist. Ask them also to help you with creating the skills.

Drafting routine documents follows the same basic workflow: feed relevant information into the workspace or reference specific URLs, and let the agents generate a Markdown file. From there, you edit it manually depending on the intended use.

Keep in mind that sensitive data does not belong in agent workflows: Weigh the risks.

---

<div class="post-metadata">

**Author:** ![technocrat](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/technocrat/32/220947_2.png) [@technocrat](https://discourse.julialang.org/u/technocrat)\
**Post date:** [October 12, 2026, 5:43pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/6 "2026-10-12T17:43:29Z")

</div>

Bite the bullet and sign up for a $20/month subscription to Claude. It’s the best all-around (And, no, I don’t get a commission.) [This link](https://claude.ai/artifact/JL79xUYfoFft3BjcdMtWXx) has Claude’s own from scratch setup, including installation of Julia for completeness.

Top gotcha: Keep your sessions short to avoid context rot because quality falls off over time, and you will see it doubling down on dead ends.

Practice project discipline. Have one general purpose dinking around project but put module-level work in separate projects. If you don’t have one already, have it walk you through setting up a free GitHub account and get into the habit of creating project repos to save your work. You’ll find that invaluable to clawing your way back to the last working stage. You have a choice of models. Currently, Sonnet is the sweet spot for general work. It’s faster and cheaper. Fable is overkill. Opus, occasionally will be helpful for more complex work.

A project is more than a folder. Have Claude “generate a Julia project” and you will stay further away from dependency hell than if you do everything in your global environment.

In the beginning of a project use the `/init` command. You can scroll through other commands with just the `/` prefix. Claude is its own help system. “Help me set up a workflow for coding in VSCode in Julia” or “set up sharing helpful functions across projects.”

Periodically ask it to review the project and suggest improvements.

Have it add docstrings to functions.

You will seldom have to resort to Google if you do this.

---

<div class="post-metadata">

**Author:** ![TimG](https://avatars.discourse-cdn.com/v4/letter/t/82dd89/32.png) [@TimG](https://discourse.julialang.org/u/TimG)\
**Post date:** [October 12, 2026, 5:46pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/7 "2026-10-12T17:46:17Z")

</div>

I asked Claude how to do this. I use VS-Code but not Pluto.

Here is what I asked:

> I have been working with Opus 5.5 (medium) to develop the julia package I maintain by giving manual prompts, responding manually, and copying code returned into VS code again manually. I want to start using agents to make the development process more efficient, so that Opus can edit, run, test, adjust itself in a sandboxed environment but still discuss with me key design choices and other decisions and never makes any PRs to my main repo - I will always do that manually. Edits are entirely local. Can you advise how best to set this up? My main tool is VS Code.

Claude gave me very clear guidance which I followed and it’s worked great. Essentially not much more than adding the Claude extension and separating plan and auto work. The best advice it gave was about avoiding git interactions I didn’t want - No PRs, etc. Don’t rely on instructions for this. Give the agent its own clone that has no GitHub credentials. Fetching a public repo still works, but pushing and opening PRs cannot happen. Deny rules are then a second layer. I pull finished branches into my primary clone and push from there manually.

It suggested using WSL for complete sandboxing and Kaimon to give the agent a persistent live Julia session, with tools for running code, running tests with pattern filtering, introspection and debugging. Set-up for these was more involved, so I didn’t adopt these suggestions - too unfamiliar, too advanced! Maybe I’ll get there in future.

(Edit: meant to reply to @Nathan_Boyer but somehow replied to @Eben60 instead!)

---

<div class="post-metadata">

**Author:** ![Nathan\_Boyer](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/nathan_boyer/32/14825_2.png) [@Nathan\_Boyer](https://discourse.julialang.org/u/Nathan_Boyer)\
**Post date:** [October 12, 2026, 6:31pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/8 "2026-10-12T18:31:51Z")

</div>

> [@technocrat](#):
>
> Bite the bullet and sign up for a $20/month subscription to Claude.

> [@Eben60](#):
>
> For configuration questions, either the built-in Gemini agent or the web version can assist.

> [@TimG](#):
>
> Claude gave me very clear guidance which I followed and it’s worked great.

If I’m wearing my tinfoil hat, _“pay them whatever they want and do whatever they say”_ sounds like we’re making their revolution a little too easy. 😅

* * *

I’m not able to justify $20/month at the moment. I won’t use it that frequently.

---

<div class="post-metadata">

**Author:** ![Eben60](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/eben60/32/13475_2.png) [@Eben60](https://discourse.julialang.org/u/Eben60)\
**Post date:** [October 12, 2026, 6:50pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/9 "2026-10-12T18:50:59Z")

</div>

> [@Nathan\_Boyer](#):
>
> pay them whatever they want

They would want more, as they make actually huge losses. It is just as much as the consumer is ready to pay.

> [@Nathan\_Boyer](#):
>
> and do whatever they say

**IMPORTANT:** Keep your own brains **on** all the time.

---

<div class="post-metadata">

**Author:** ![sylvaticus](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/sylvaticus/32/203883_2.png) [@sylvaticus](https://discourse.julialang.org/u/sylvaticus)\
**Post date:** [October 12, 2026, 7:08pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/10 "2026-10-12T19:08:39Z")

</div>

> [@Nathan\_Boyer](#):
>
> I’m not able to justify $20/month at the moment. I won’t use it that frequently.

But that will change once you try it 🤣🤣🤣..

---

<div class="post-metadata">

**Author:** ![Eben60](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/eben60/32/13475_2.png) [@Eben60](https://discourse.julialang.org/u/Eben60)\
**Post date:** [October 12, 2026, 7:17pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/11 "2026-10-12T19:17:23Z")

</div>

> [@Nathan\_Boyer](#):
>
> I’m not able to justify $20/month at the moment. I won’t use it that frequently.

You might get something useful for $10, but free is probably useless for coding. Also, you can pay just for one month, then cancel.

---

<div class="post-metadata">

**Author:** ![joa-quim](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/joa-quim/32/227_2.png) [@joa-quim](https://discourse.julialang.org/u/joa-quim)\
**Post date:** [October 12, 2026, 8:00pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/12 "2026-10-12T20:00:33Z")

</div>

> [@sylvaticus](#):
>
> > [@Nathan\_Boyer](#):
> >
> > I’m not able to justify $20/month at the moment. I won’t use it that frequently.
> 
> Bet that will change once you try 🤣🤣🤣..

I was about to say similar thing. “That’s because you didn’t try it yet”. Just forget about the others.

---

<div class="post-metadata">

**Author:** ![technocrat](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/technocrat/32/220947_2.png) [@technocrat](https://discourse.julialang.org/u/technocrat)\
**Post date:** [October 12, 2026, 8:30pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/13 "2026-10-12T20:30:15Z")

</div>

Cell phones used to be “too expensive.”

---

<div class="post-metadata">

**Author:** ![Alex-Scofield](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/alex-scofield/32/222449_2.png) [@Alex-Scofield](https://discourse.julialang.org/u/Alex-Scofield)\
**Post date:** [October 12, 2026, 9:23pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/14 "2026-10-12T21:23:25Z")

</div>

To be fair, you can get _decent_ results for simple tasks with the free tier of OpenCode, notably with the Big Pickle model (although you should know that your data will be used for training). I’ve never had the need for powerful models yet, as I am a bit of an AI skeptic and as I don’t actually code that much and can currently afford to be slow and take my time understanding all of my code. For simple things such as taking care of boilerplate and simple prototyping, these models could be enough. They definitely force you to be more in the loop than what would be the case with frontier models, which can ironically be an advantage. YMMV in any case, but I would say to OP that they might be worth a try!

---

<div class="post-metadata">

**Author:** ![ufechner7](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/ufechner7/32/51363_2.png) [@ufechner7](https://discourse.julialang.org/u/ufechner7)\
**Post date:** [October 12, 2026, 9:55pm UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/15 "2026-10-12T21:55:32Z")

</div>

It depends a bit on if you have any free access to any AI tools because you work for university or a startup for example, or not. If not… Well, the commercial providers also have some free plans, but they are quite limited.

How much do you want to spend?

For 5 EUR/ dollars you could get an OpenRouter account and use a cheap, Chinese model. There are also cheap US or European models, but they are less powerful.

So I would get an OpenRouter account, generate a key and use [DeepSeek V4.1 Flash - API Pricing & Benchmarks | OpenRouter](https://openrouter.ai/deepseek/deepseek-v4.1-flash) . Do you think that is a good first step? If yes, I could explain how to proceed.

The advantage of OpenRouter is that you can try all kind of models if you want to before deciding to which one you want to stick. If you know which one you want, a monthly subscription is usually much cheaper, depending on your usage.

In a next step I would then integrate that in VSCode, in case you are using VSCode. Do you?

---

<div class="post-metadata">

**Author:** ![adienes](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/adienes/32/37459_2.png) [@adienes](https://discourse.julialang.org/u/adienes)\
**Post date:** [October 13, 2026, 12:40am UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/16 "2026-10-13T00:40:10Z")

</div>

to be completely frank, I think Anthropic and OpenAI’s models are miles and bounds better than any other option.

I know there is a lot of hype over various other options that may be smaller/cheaper/faster (e.g. GLM, Qwen, DeepSeek, etc.) but I really cannot think anything but that you will get the most bang for your buck, by far, by spending $20 for a month of Claude Pro or ChatGPT Plus

---

<div class="post-metadata">

**Author:** ![joa-quim](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/joa-quim/32/227_2.png) [@joa-quim](https://discourse.julialang.org/u/joa-quim)\
**Post date:** [October 13, 2026, 12:53am UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/17 "2026-10-13T00:53:15Z")

</div>

> [@adienes](#):
>
> I think Anthropic and OpenAI’s models are miles and bounds better than any other option.

And Claude is miles and miles better than GPT (any)

---

<div class="post-metadata">

**Author:** ![Nathan\_Boyer](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/nathan_boyer/32/14825_2.png) [@Nathan\_Boyer](https://discourse.julialang.org/u/Nathan_Boyer)\
**Post date:** [October 13, 2026, 12:56am UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/18 "2026-10-13T00:56:28Z")

</div>

What about Copilot? GitHub Copilot has free and $10 tiers. I imagine it would integrate the best with VS Code and GitHub. I also have access to some kind of Microsoft Copilot through Windows.

---

<div class="post-metadata">

**Author:** ![adienes](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/adienes/32/37459_2.png) [@adienes](https://discourse.julialang.org/u/adienes)\
**Post date:** [October 13, 2026, 1:13am UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/19 "2026-10-13T01:13:00Z")

</div>

I would encourage you to try whatever is most convenient and useful for you. There’s no need to use certain tools just to say you did 🙂

> I imagine it would integrate the best

but that being said, there’s not a task in the world I wouldn’t trust Claude or Codex to do better than any special-purposed AI. they are “generalists” that also happen to be better than all the specialists at everything.

---

<div class="post-metadata">

**Author:** ![ufechner7](https://sea2.discourse-cdn.com/julialang/user_avatar/discourse.julialang.org/ufechner7/32/51363_2.png) [@ufechner7](https://discourse.julialang.org/u/ufechner7)\
**Post date:** [October 13, 2026, 5:32am UTC](https://discourse.julialang.org/t/how-to-start-using-ai/139973/20 "2026-10-13T05:32:36Z")

</div>

> [@Nathan\_Boyer](#):
>
> What about Copilot?

I also used Copilot first, but 2 or 3 months ago they started to charge full prices for most models and I run out of credit within one or two days. And they don’t offer the cheap Chinese models. If you want to try out things for 5 EUR / dollars, use openrouter, much larger choice of models than Copilot.

[Next page](https://discourse.julialang.org/t/how-to-start-using-ai/139973.md?page=2)
