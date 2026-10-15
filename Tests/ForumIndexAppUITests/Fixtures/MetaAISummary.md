# AI agents signing up for accounts

**URL:** <https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624>\
**Category:** Community Building\
**Created:** [October 13, 2026, 10:44pm UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624 "2026-10-13T22:44:25Z")\
**Posts on this page:** 8\
**Page:** 1

## AI-generated summary

The discussion addresses the growing concern of AI agents automatically creating accounts on Discourse forums. [scottfsmith](/t/-/414624/1) reports encountering an account from `ilands.app` that posted strange content and claimed to be an agent, prompting a query about community-wide trends and mitigation strategies. [NateDhaliwal](/t/-/414624/2) suggests using the Discourse AI plugin's spam detection features, though [scottfsmith](/t/-/414624/3) clarifies that this is distinct from humans pasting AI responses, as fully autonomous agents produce consistent AI-generated content.

Several technical solutions are proposed. [Lilly](/t/-/414624/4) recommends implementing Captchas, while [nickdb](/t/-/414624/5) advises a layered approach: identifying user-agents, blocking known crawlers via IP lists, raising entry difficulty for new users, and curating example posts to help classify potential AI bots. [merefield](/t/-/414624/6) notes that this phenomenon is already occurring.

[scottfsmith](/t/-/414624/7) shares their experience adding sign-up questions, which initially blocked most bots but failed against newer AI agents capable of answering them. They acknowledge that Captchas may become less effective as AI improves but plan to implement them immediately. Regarding the Discourse AI plugin, they initially avoided it due to costs but now consider it necessary to "fight fire with fire." In response, [nickdb](/t/-/414624/8) reassures that token costs are decreasing and can be managed by focusing AI resources on high-risk areas like new user registration rather than running globally across all trust levels. He estimates that sensible configuration results in low daily costs (e.g., $1/day) and highlights the plugin's ability to estimate usage based on model selection.

<div class="post-metadata">

**Author:** ![scottfsmith](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/scottfsmith/32/50976_2.png) [@scottfsmith](https://meta.discourse.org/u/scottfsmith)\
**Post date:** [October 13, 2026, 10:44pm UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/1 "2026-10-13T22:44:25Z")

</div>

I am concerned that there could be a big wave of AI agents coming that will be making accounts. We just got one today from ilands.app which is some kind of LLM agent. They posted some random strange stuff which stuck out and we noticed they mentioned they were an agent and deleted them. Is anyone else seeing this and any plans to deal with it?

---

<div class="post-metadata">

**Author:** ![NateDhaliwal](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/natedhaliwal/32/313494_2.png) [@NateDhaliwal](https://meta.discourse.org/u/NateDhaliwal)\
**Post date:** [October 14, 2026, 1:05am UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/2 "2026-10-14T01:05:17Z")

</div>

Take a look at:

> [@How do you handle AI responses in your Community?](https://meta.discourse.org/t/how-do-you-handle-ai-responses-in-your-community/386953):
>
> Hello everyone! I am wonder how other community managers handle AI responses in discussion and questions type categories. Our current policy is that the usage of AI is okay as long as you validate the response. After seeing some responses like this for example, I am starting to think I want to create a more strict policy against AI. Good question, I’ll help you call the Slack API to post a message to a channel. Here’s how to do it: Basic API Request You’ll use the chat.postMessage endpoint…

I wonder if you could use the AI plugin’s [Spam detection](https://meta.discourse.org/t/discourse-ai-spam-detection/343541) to recognise AI-generated content. The AI helper on posts here on Meta is pretty astute when it comes to doing that.

---

<div class="post-metadata">

**Author:** ![scottfsmith](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/scottfsmith/32/50976_2.png) [@scottfsmith](https://meta.discourse.org/u/scottfsmith)\
**Post date:** [October 14, 2026, 2:05am UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/3 "2026-10-14T02:05:49Z")

</div>

I thought that was more about human users pasting in AI answers, I’m asking here about 100% AI accounts.

It would be easier to recognize them compared to a human pasting in AI since the human would mix in some non-AI in that and other posts whereas the AI agent would be all AI content.

---

<div class="post-metadata">

**Author:** ![Lilly](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/lilly/32/575047_2.png) [@Lilly](https://meta.discourse.org/u/Lilly)\
**Post date:** [October 14, 2026, 2:44am UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/4 "2026-10-14T02:44:17Z")

</div>

set up discourse captcha

> [@Discourse Captcha](https://meta.discourse.org/t/discourse-captcha/291383):
>
> discourseSummary Discourse Captcha adds CAPTCHA challenge support to the local sign-up form, with support for multiple providers including hCaptcha and reCAPTCHA.open_bookInstall guide This plugin is bundled with Discourse core. There is no need to install it separately.discourse2 Hosted by us? This plugin is available on our Pro, Business, and Enterprise plans. [https://www.discourse.org/plugins/captcha](https://www.discourse.org/plugins/captcha)Supported providers The plugin supports the following CAPT…

---

<div class="post-metadata">

**Author:** ![nickdb](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/nickdb/32/444510_2.png) [@nickdb](https://meta.discourse.org/u/nickdb)\
**Post date:** [October 14, 2026, 5:33am UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/5 "2026-10-14T05:33:57Z")

</div>

Identify the user-agents in use (they often, but not always) announce themselves.

Use crawler blocks lists, ip blocking.

Captcha helps.

You have to raise the difficulty level for entry and layer checks for new users, ones that don’t overly annoy actual users or raise the moderation workload.

Bot checking can be effective but it helps to build up a curated list of example posts that any AI based bot can use to classify a user as being a potential AI.

Welcome to the new digital era, ain’t it grand 😉

---

<div class="post-metadata">

**Author:** ![merefield](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/merefield/32/176214_2.png) [@merefield](https://meta.discourse.org/u/merefield)\
**Post date:** [October 14, 2026, 7:57am UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/6 "2026-10-14T07:57:52Z")

</div>

This is already happening.

---

<div class="post-metadata">

**Author:** ![scottfsmith](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/scottfsmith/32/50976_2.png) [@scottfsmith](https://meta.discourse.org/u/scottfsmith)\
**Post date:** [October 14, 2026, 12:46pm UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/7 "2026-10-14T12:46:30Z")

</div>

I did add some questions to fill in at sign-up which eliminated nearly all of the bots. The more recent agents can answer them though. AI is also quickly getting better at Captchas, I doubt that line of defense is going to last long. But it’s probably worth hooking up now, thanks for the suggestion. I’ve been avoiding the Discourse AI plugin to avoid paying yet more $$ (the free plans won’t be free very long), but probably in the long term I’ll need to pay up and fight fire with fire.

---

<div class="post-metadata">

**Author:** ![nickdb](https://sea3.discourse-cdn.com/meta/user_avatar/meta.discourse.org/nickdb/32/444510_2.png) [@nickdb](https://meta.discourse.org/u/nickdb)\
**Post date:** [October 14, 2026, 12:53pm UTC](https://meta.discourse.org/t/ai-agents-signing-up-for-accounts/414624/8 "2026-10-14T12:53:30Z")

</div>

The token costs keep coming down. We focus the bots on the problem areas so they don’t chew tokens running globally across trust levels and all categories.

It is new(er) users that are the entry point.

We’re consuming a whopping $1 per day.

Just be sensible with the scope and the model used, most tasks don’t need significant reasoning efforts.

Punch in the token costs and the usage figures will be estimated for you in the AI plugin.
