# Proposal: trimming down the Ansible community package and collection removal roadmap

**URL:** <https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563>\
**Category:** Project Discussions\
**Tags:** azure, windows, gcp, community-wg, aws, network, galaxy-ng, kubernetes\
**Created:** [October 30, 2026, 10:03am UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563 "2026-10-30T10:03:41Z")\
**Posts on this page:** 7\
**Page:** 1

<div class="post-metadata">

**Author:** ![Andersson007](https://sea1.discourse-cdn.com/ansible/user_avatar/forum.ansible.com/andersson007/32/89_2.png) [@Andersson007](https://forum.ansible.com/u/Andersson007)\
**Post date:** [October 30, 2026, 10:03am UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563/1 "2026-10-30T10:03:41Z")

</div>

Following the adoption of the [new collection inclusion criteria](https://docs.ansible.com/projects/ansible/devel/community/steering/community_steering_committee.html#collection-inclusion-criteria-and-process), I propose discussing a roadmap to remove collections that no longer meet the criteria from the Ansible community package.

**PR:** [[Steering Committee vote is NEEDED before merge] ccollection\_removal\_roadmap.rst: add Ansible community package collections removal roadmap by Andersson007 · Pull Request #4113 · ansible/ansible-documentation · GitHub](https://github.com/ansible/ansible-documentation/pull/4113)

This topic targets step 3 from the [original transition plan](https://forum.ansible.com/t/vote-ended-2026-10-08-proposal-trim-and-restrict-the-ansible-community-package-down-to-a-steering-committee-selected-set/46339/9).

## Summary

The [current package](https://github.com/ansible-community/ansible-build-data/blob/main/15/ansible.in) includes 87 active collections. After applying the inclusion criteria, 17 collections qualify to stay. The remaining 70 are proposed for removal.

## Collections proposed to keep (17)

- **Core Ansible infrastructure:** ansible.netcommon, ansible.utils, community.general, community.library\_inventory\_filtering\_v1

- **Operating systems:** ansible.posix, ansible.windows, community.windows

- **Major cloud providers:** amazon.aws, community.aws, azure.azcollection, google.cloud

- **Containerization:** community.docker, containers.podman, kubernetes.core

- **Cryptography:** community.crypto

- **DNS:** community.dns

- **Virtualization:** community.libvirt

## Rationale for removing the rest

Each removed collection falls into at least one of:

- **Vendor-specific** without being widely enough adopted to qualify for the infrastructure exception (unlike AWS, Azure, GCP).
- **Domain-specific or niche** , not broadly applicable across industries.
- **Application-layer** (databases, message brokers, monitoring tools) rather than foundational infrastructure.

## Deprecation timeline

- **Announce deprecation:** Ansible community package 14 (current release).
- **Remove from package:** Ansible community package 18 (~2 years / 4 major releases later).

This gives users roughly two years to adjust CI/CD pipelines and add explicit `ansible-galaxy collection install` steps. The collections will remain available on Galaxy.

## What this means for users

- Removed collections **stay on Galaxy** and can be installed individually.
- Existing playbooks and roles continue to work after installing the needed collections explicitly.
- No functionality is lost, only the bundling changes.

## What we need to decide now

To resolve this topic we need to make decisions on the following questions in order:

1. Do we support trimming down the package? If yes, proceed to the next questions.
2. Do we keep ansible-core + only the suggested collections? Should we adjust the list (add/remove anything)?
3. Do we use the suggested deprecation timeline?

Please share your thoughts on the above questions in comments. Wording suggestions are appreciated in the [PR](https://github.com/ansible/ansible-documentation/pull/4113).

Then we can vote on merging the PR.

Thank you!

---

<div class="post-metadata">

**Author:** ![russoz](https://sea1.discourse-cdn.com/ansible/user_avatar/forum.ansible.com/russoz/32/127_2.png) [@russoz](https://forum.ansible.com/u/russoz)\
**Post date:** [October 30, 2026, 10:39am UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563/2 "2026-10-30T10:39:08Z")

</div>

> [@Andersson007](#):
>
> - Announce deprecation

I believe we should not only “announce” but also advertise periodically (monthly? 3 months? 6months ~ at major versions’ releases?), reminding users about the deprecation.

> [@Andersson007](#):
>
> 1. Do we support trimming down the package? If yes, proceed to the next questions.

YES!

> [@Andersson007](#):
>
> 1. Do we keep ansible-core + only the suggested collections? Should we adjust the list (add/remove anything)?

Not something that I would defend fiercely, but maybe add open source on-prem virtualisation platforms, like Openstack and Proxmox.

> [@Andersson007](#):
>
> 1. Do we use the suggested deprecation timeline?

It looks good to me.

---

<div class="post-metadata">

**Author:** ![felixfontein](https://sea1.discourse-cdn.com/ansible/user_avatar/forum.ansible.com/felixfontein/32/7530_2.png) [@felixfontein](https://forum.ansible.com/u/felixfontein)\
**Post date:** [October 30, 2026, 12:14pm UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563/3 "2026-10-30T12:14:37Z")

</div>

Since this is a very large change to the Ansible community package, I propose to slow this discussion down and not decide anything until very late in the Ansible 14 release cycle, or even just for 15.0.0 (or one of its pre-releases). This gives more interested parties (users, OS packagers, affected collection developers) time to take part in the discussion (if they want to).

---

<div class="post-metadata">

**Author:** ![felixfontein](https://sea1.discourse-cdn.com/ansible/user_avatar/forum.ansible.com/felixfontein/32/7530_2.png) [@felixfontein](https://forum.ansible.com/u/felixfontein)\
**Post date:** [October 30, 2026, 12:16pm UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563/4 "2026-10-30T12:16:11Z")

</div>

(Sorry for accidentally editing the original post, I reverted my changes. I still have no idea how I managed to edit it instead of writing a reply…)

---

<div class="post-metadata">

**Author:** ![mikemorency](https://sea1.discourse-cdn.com/ansible/user_avatar/forum.ansible.com/mikemorency/32/2672_2.png) [@mikemorency](https://forum.ansible.com/u/mikemorency)\
**Post date:** [October 30, 2026, 1:18pm UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563/5 "2026-10-30T13:18:37Z")

</div>

> [@Andersson007](#):
>
> ## **Rationale for removing the rest**
> 
> - **Application-layer** (databases, message brokers, monitoring tools) rather than foundational infrastructure.

I think this should be reconsidered.

1. The new criteria does not explicitly deny application layer, nor does it explicitly say only infrastructure layer
2. Limiting the collections to just infrastructure deters non-systems people from trying Ansible (for example, a DBA or developer), as well as limits a users ability to see the full “chain” of automation for their full stack.

Surely a database or monitoring tool is considered “foundational”

---

<div class="post-metadata">

**Author:** ![Andersson007](https://sea1.discourse-cdn.com/ansible/user_avatar/forum.ansible.com/andersson007/32/89_2.png) [@Andersson007](https://forum.ansible.com/u/Andersson007)\
**Post date:** [October 30, 2026, 1:22pm UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563/6 "2026-10-30T13:22:57Z")

</div>

@russoz @felixfontein @mikemorency great feedback, thank you! I agree with all the statements. Let’s collect more feedback and then I’ll try to incorporate overlapping opinions into the PR

---

<div class="post-metadata">

**Author:** ![felixfontein](https://sea1.discourse-cdn.com/ansible/user_avatar/forum.ansible.com/felixfontein/32/7530_2.png) [@felixfontein](https://forum.ansible.com/u/felixfontein)\
**Post date:** [October 30, 2026, 1:43pm UTC](https://forum.ansible.com/t/proposal-trimming-down-the-ansible-community-package-and-collection-removal-roadmap/46563/7 "2026-10-30T13:43:34Z")

</div>

I’ve been thinking a lot about what to include, or how to avoid ending up with basically the same package size as before 😉

I agree that some more collections (proxmox/openstack for virtualization, mysql/mariadb/postgres for databases, … no idea what for monitoring, …) should likely be part of the package. I’m also wondering about network collections. I think someone mentioned that among network infra people it is quite common to install the Ansible community package since it contains a lot of networking stuff. The proposal above removes it all, despite networking being quite foundational (most servers would have nothing to do without it 😉 ). But with this chain of arguments, you end up with good arguments to keep most things…

How about the (in the past, mentioned more than once) scenario of creating multiple Ansible community packages? Then we could have ansible-network that contains ansible-core + ansible.netcommon + a set of network connections, ansible-cloud that contains ansible-core + amazon/community.aws, azure.azcollection, google.could, etc., and ansible-virtualization that contains …, ansible-monitoring that contains …, and so on. That would provide a smaller list of Ansible community packages that are tailored for different use-cases. Most people would install two or more of these.

(There shouldn’t be too many, otherwise we could just package collections as PyPI packages… Also the more there are, the more work there is for us…)

(Also it’s too bad that the names ansible-core and ansible-base as PyPI packages are already taken, they could be used for more foundational bundles 😉 )
