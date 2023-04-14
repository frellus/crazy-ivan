# Crazy Ivan - Completely Paranoid Monitoring

## Overview

`Crazy Ivan` is a stand-alone, simple monitoring system for the paranoid which can be extended for any environment to run batches of checks. This is the monitoring system you didn't know you needed, but you do.

## "Who watches the Watchers?"
Everyone uses monitoring systems in a production environments, and yet we have all experienced gaps in monitoring which have led to outages being raised by users. Why is this? The answer is simple: most "observability" platforms and concepts, as invaluable as they are, are centered around the concept of just that: observe. Gather data. Look at that data. Filter the noise for signals and raise exceptions. Correlate dependencies to the related consumers.

Nothing can or should wholy replace these systems, you pick the best tool for the right job - whether it be Grafana, DataDog, Cloudwatch, etc.

The flaw though in these systems tends to be that they rely on gathing a lot of data passively - logs, application traces and metrics (scraped or pushed). Often the infrastructure sitting behind them itself is complicated enough where you better monitor the monitor because it's just as likely to have an issue as it's wards. So we're left with a dilema: who watches the watchers? 

One way is to have a [dead man's switch](https://en.wikipedia.org/wiki/Dead_man%27s_switch), where a secondary system (ideally the downstream alert sending system) detects the loss of a heartbeat signal from the monitoring system, and would then dutifully send an alert to a human that there is loss of monitoring. That is certainly a good idea, although few people employ this in practicality (it's more prevalent to have blind trust in the monitoring systems, especially when they're run by a third party). Still that's not the primary issue this project covers, because the total loss of a monitoring system is easier to detect, especially when engineers are using it as a troubleshooting and visibility into services regularly.

What we believe is truely missing are checks outside of these passive monitoring system's scope. Drive the system to see if it's working.

## What do you mean, "Checks"?
Take, for an analogy, a car. You *could* have a fancy [device](https://us.bluedriver.com/pages/bluedriver) that hooks up to the car's CAN bus which gives you all sorts of diagnostics (they *are* pretty slick, actually ... I'd suggest getting one). Ask yourself though: if you could see the engine RPM, Mass Air Flow rate, speed gauges, error codes would it *really* tell you the car is healthy to drive? It's a pretty good diagnostic tool for sure, but really the way you know a car is good is: ***YOU DRIVE IT!!***

The same holds true of systems. We monitor each of the components and services in the infrastructure with sensors. We look for signal in the noise, but the best test is always to just run work through it. That's all `Crazy Ivan` is -- it's an active monitoring system. Rather than trying to gather signals from the passive data, `Crazy Ivan` surfaces issues through active use monitoring. Here's some examples:

* Have a database? Have `Crazy Ivan` run a SQL check every hour
* Kubernetes? Run common kubectl commands against it, like you do as an administrator and make sure the expected results come back
* Have an NFS storage array? Write a short scritp to mount a filesystem do a bunch of I/O
* HDFS? Run a myriad of HDFS commands to create, write, read, delete files
* etc.

Active monitoring becomes even more critical as the scale (and complexity!) of an environment increases. What if you had not one NFS server, but a hundred of them. Of course you have logs going someplace for them all, but how do you *really* know when they're slow if you don't actually run a test and measure the timing?

## So What is Crazy Ivan?

`Crazy Ivan` is designed to be an execution engine for paranoid, active service checks. The design goals are simple:

* execute active service checks on a periodic basis
* require as little development overhead on an SRE / DevOps team - *a simple shell script often works, for example*
* DRY - *write one generic test on a set of targets and variable permutations*
* extremely extensible - *tests can be written in any language so long as their output conforms to what Crazy Ivan needs*
* highly resiliant, self-contained with few external dependencies - *lowers the risk of a dependent piece of infrastructure causing an outage*
* independent - *works completely out of band of your current monitoring system(s)*
* higly parallelized - *tests are run in parallel and results are correlated into an overall point-in-time report*
* performant - *one small VM will get you thousands of checks*
* fault tolerant - *a failing or hung check doesn't prevent other checks from being run*

## OK, So ... Why is it Called "Crazy Ivan"?!

The phrase "Crazy Ivan"[^1] was a cold war term which originated from a manuver the Soviet submarines would do to "clear their **baffles**", [baffles](https://en.wikipedia.org/wiki/Baffles_(submarine)) being the term used to describe the blind spot behind submarines traditionally not covered by sonar.

<img src="crazy_ivan/priv/images/480px-Submarine_baffles.png" alt="A submarine's baffle space" width="25%" height="25%"/>[^2]

Soviet subs would periodically make a sudden, hard turn to check if an enemy attack submarine was stalking it from behind, a favorable firing position for any hunter. The American submarines could only go undetected by shutting off their engines and "going quiet" by drifting, which posed a huge risk of colliding into the forward sub. This was popularized in the 1990 [Tom Clancy](https://en.wikipedia.org/wiki/Tom_Clancy) movie, ["The Hunt for Red October"](https://en.wikipedia.org/wiki/The_Hunt_for_Red_October_(film)) which portrayed this as a paranoid move, almost like a spy afraid of his shadow. In later years it became obsolete with the additon of a towed-array sonar.

<img src="crazy_ivan/priv/images/crazy-ivan-scene.png" alt="Hunt for Red October scene" width="50%" height="50%"/>

---

# A Somewhat Simple Example

Every check requires an executable, and a manifest (configuration). 

Let's say you have an API service, run from an nginx server and dependent on a PostgreSQL database (there's a network in there somewhere too). Now, you might have monitoring from the web server looking at access logs and reporting on a particular pattern. There also could be [Prometheus](https://prometheus.io) metrics the webserver returns showing it's alive and how much activity it has had in terms of operations. Maybe the you are using [pgDash](https://pgdash.io) to monitor database. What about the network? SNMP monitoring on every switch gives us telemety there. Very sophisticated!

Really though, what happens when your users tell you the API is "slow", do you go and look through the metrics dashboard? Certainly, but you're also just as likely to fire up a web browser and try to hit the API yourself. Really, when you get down to it, running someting like `curl` could give you as much information as anything.

The problem is, if you wrote a short script to do `curl` against your one critical API endpoint, it would feel extremely bespoke since this is just one thing in your environment, although you have to admit: running `time curl` pretty much confirms the user's report that it's slow. What would that script look like? Maybe something like this:

```bash
#!/bin/bash

curl --fail --silent "https://api.example.com/v1/get-users" > /dev/null

if [ $? -eq 0 ]; then
    exit 0
else
    echo "The API server isn't up" | mailx -s "alert: api service" admins@example.com
    exit 1
fi
```

Problem is scheduling this to run, it's just so specific, there's no timing built into it (you might have to swap it out for something like Python and call `subprocess.run()` to get the timing of the curl command effectively). It's not really useful or maintainable, and in the end we would all say "this is a dumb idea... I have a ton of monitoring on my systems, I need to find a KPI (SLI) to monitor harder!".

Let's not give up though becuase if we *could* run `curl` periodically and efficiently, it has value in addition to the monitoring system. This is where the concept around a `Crazy Ivan` check is exactly that. That one `curl` command excercised the entire datapath - from network to webserver, API service and back-end. Oh, and the database! So we could essentially infer that the system is healthy if write a script like this, as hardcoded and lame as it is, run it from cron on a VM somewhere maybe...? Check e-mail to know the curl failed? No way! This is where `Crazy Ivan` steps in.

A `Crazy Ivan` check could basically be that same idea of a shell script, just bit more generic. Maybe in this case, let's even add a few more API endpoints to hit in a loop while we're at it. Here's the `Crazy Ivan` based script:

```bash
#!/bin/bash

# run against the six common API endpoints
for method in users roles inventory tasks alerts messages
    curl --fail --silent -X GET "${target}/${method}" > /dev/null
    return_code=$?
    if [ $return_code -ne 0 ]; then
        echo "%IVAN% FAIL on ${target} for method ${method}"     # optional information to log 
        exit $return_code                                        # only the return code is actually requrired - 0 for pass, anything else is a fail
    fi
done

exit 0
```

Any time a script, program or command executed from `Crazy Ivan` exits with a non-zero exit code, it is assumed to be failed. The optional line that echos `%IVAN%` allows us to pass back a string we can use to later give an explicit description of the failure for summation purposes (described later).

Now we need a control file that Crazy Ivan uses to run that script. It'll define the variable target(s), and pass in environment variables when it's executed. It'll measure the time it takes to run, we can define some expected timing as well so we know even if a check passes if it takes longer than expected we can fail, and we can tell it how often to run.

Sample config file:
```yaml
---

- name: api-checks                             # Name of this check, must be globally unique
    description: Check our API services        # friendly description (appears in the web report)
    method:
        script: api/api-checks.sh              # path to the script from Crazy Ivan's root (defined globally)
    targets:                                   # target environment variables to be passed to the script, each as $target
        - http://api.example.com/api/v3/                   
        - http://admin.example.com/api/v2/               
        - http://old.example.com/api/v2/                   
    env:                                       # optional list of ENVIRONMENT variables to pass to the shell environment
        api-key:       $secret(api-key)                         
        api-username:  svc-crazy-ivan                            
    slo:                                       # Service Level Objectives
        expected: 10s                          # time this check is expected to take
        tolerance_high: 25%                    # latency timing can be +/- the expected slo
        timeout: 60s                           # check should die as "failed" if this timeout is reached
    schedule:                                  # Schedule to Run on 
        method: sequential                     # run against all the above targets one at a time, not in parallel
        frequency:
            - random_hourly                    # check should run about every hour, but add some randomness to it +/- some mins
        except:
            - weekends                         # don't run on the weekends
    alert: true                                # send an alert if this check fails
```

 The idea is to be as low overhead on writing scripts as possible so as to encourage others in our team to contribute as well. Two files is all that's needed - an executable and a config. You'll notice we defined three different targets in the config as well, as we realized there are a few other API servers that would benefit from active monitoring. Now we have 18 checks that are running in our environment (six API endpoints are checked across three different API servers). It's starting to feel like we are getting Infrastructure test coverage now, not just monitoring.

 By writing that one generic "active" check logic script, and using the DSL of the config file, Crazy Ivan is responsible to make sure those 3 targets are faithfully checked every day about hourly (`random_hourly` adds a bit of variation on the checks so we're not always hitting the same time of day), except on the weekends. If any of the checks should fail, the whole check `api-checks` is marked as failed in the category `api` (implied from the directory the check is in). 
 
 Additionally you can see in the configuration file, we're also expecting an SLO of about 10s for the check executable to run, and we can go 25% higher than that before there's a failure generated (it could have also been defined a a pure multiplier of the duration, like `2`)
 
 So with these two simple filesm we are regularly excercising the whole chain of system dependencies - from API code, web server network and database, as well as measuring the service time directly. Paranoid? You bet! We want to detect issues, and using the data path that a client would use allows us to effectively do this.
 
 Does Crazy Ivan replace the monitoring we have on each of those components? Not at all, but it does excercise the entire path from a client, which is a huge advantage. As intended, this is a very simple example. The tests can be run as scriptlets, similar to how you would write unit tests on code. The method of execution and the complexity, or lack of it, is entirely up to you. These are unit tests on the service and infrastructure, and should be thought of as being as atomic as possible. At the end of the day, one command like `curl` is telling us a lot of inforamtion, and with Crazy Ivan we can run that across our environment without much development overhead at all.

 This case was `curl`, a similar example could have been to check the PostgreSQL database using `psql` - no fancy massive monitoring tools required just a command, username and password, and a SQL statement(s) to test the responsiveness of our database in a satisfying way and we're off. If we have a hundred dataase servers, that one script could be used to check them all. Crazy? Crazy simple!!

>  :information_source: Note: In some ways you might make some comparison between something like [Ansible](https://www.ansible.com) and Tower - and you wouldn't be far off. Putting all the complexity into the DSL (YAML config file) and separating out the execution part to make it as generic as possible, `Crazy Ivan` is just the `Ansible Tower` equivalent, but it's focus is on health checks. Ansible is not great at running external commands outside the DSL and capturing outputs. The whole focus of `Crazy Ivan` is not configuration, it's the way you test drive your environment and services.

## Interfacing with Crazy Ivan

There is (will be) a dashboard, an API as well as a nice LiveView front-end web UI which will retrieve information on the system as well as let you control the behavior of Crazy Ivan. (TODO: more on this later)

### A simple Dev Loop

So our dev loop is simple!
1. write generic scriptlet (can be any generated binary or executable program, such as a Python or Golang binary, or even just a single shell command). The key is that the execution logic should be as simple as possible.
   
2. give it a name and descibe it (this is how it'll appear on the dashboard, as well as how it is categorized)
   
3. define the way the check(s) should be run including:
   - targets (can also be a list of targets in a file, or database source)
   - SLO, "Service Level Objective"
   - any environment variables or special secret keys to make it run

4. commit to git repo
   
5. have a production environment that has a clone of this repo and is able to pull from main as a way of running

## Crazy Ivan's Architecture and Development Methodology

`Crazy Ivan` is developed in [Elixir](https://elixir-lang.org) because the [BEAM](https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine)), in my humble opinion, is absolutely awesome as a systems automation language with it's lightware process and concurrency model. Likewise, [Phoenix](https://www.phoenixframework.org) + [Tailwind CSS](https://tailwindcss.com) allows for creating an extremely nice, simple dashboard to display the live status of checks natively in Elixir without any real JavaScript.

The other key development aspect that [OTP](https://en.wikipedia.org/wiki/Open_Telecom_Platform) gives us is the [Actor](https://en.wikipedia.org/wiki/Actor_model) Model, which lends itself quite nicely to this problem. Each check will be a separate OTP process which is always running (most of the time idle). These processes will act as exectors to ensure the checks are being run as defined, and are being published back to the collection point. To do this, we do **NOT** need a separate message bus, as Elixir and Phoenix have this builtin, so we are keeping our Crazy Ivan environment as self-sustaining as possible. The most complicated observability platforms in the world usually depend on architectural components to run, such as Kafka, Redis or such, and in our case we do not want to have any dependencies since that is exactly what we are checking! How bad would it be if we were checking the health of a database but we depended on the database itself to run?!

For that point alone, what a blessing Elixir is with all the things it has built in. For our design of Crazy Ivan, we can simplify our design so to run the engine you do not need any of these:
* database
* message bus
* middleware of any kind
* scheduling engine

To that end, it is **HIGHLY** recommended that you do not run Crazy Ivan inside of a Kubernetes, or other Container-based distributed framework. The best way to run it would be in a VM or on a bare metal host. No external dependencies should be used. If you wanted to run checks across all your hosts, for example, that ssh was working you could but to build that hostlist you should avoid as much as possible tying another system in here like a database for inventory. A better idea would be to have a scipt which pulls the inventory out of a file that's commited to the repo, or at worst uses some sort of DNS discovery. The point here is to keep it as air gapped from the rest of the environment as possible so as to avoid a cascading failure. Think how much it would hurt if you said, "We didn't know the database was offline because Crazy Ivan depends on it to get it's list of monitoring targets"

> A small aside: if you don't know about [Elixir](https://elixir-lang.org) or [Phoenix](https://www.phoenixframework.org), stop whatever you are doing and watch this talk, ["The Soul of Erlang and Elixir"](https://youtu.be/JvBT4XBdoUE) by Sasa Juric. It's what originally inspired me to start learning Elixir and about the BEAM, thinking about the implications of such capabilities with true fault tolerance and parallelism it brings.

### Roadmap / TODO List

- [X] Project initiation [**April 13th, 2023**]
- [ ] Stawman - Crazy Ivan's first automated test running
- [ ] Exended DSL
- [ ] Parallel checks, file-based inventory
- [ ] Unit Testing
- [ ] Much better documentation
- [ ] Web UI
- [ ] CLI tool
- [ ] Docker image published
- [ ] Publish Blog Post

### Backstory

`Crazy Ivan` came about as a project which, conceptionally, I've found myself writing in almost every infrastructure environment I've worked in.

A short 20 some years ago, while working in an infrastructure team for a global bank and trading firm, we were challenged one day to run health check prior to the start of trading. An issue had happened with the infrastructure systems causing an "outage" to traders (who are insane in the best of circumstances), and unfortunately there was also a small gap in our monitoring. We fixed it, of course, but the amount of flack we got was high, and the top execs demanded that IT be in the office running checks every morning before the "open" (of the markets).

"But we have monitoring going 24x7! We'll know if something is broken!!" we cried, as no one in IT wanted to be up and in the office checking out storage and databases at 6:30 in the morning.

"You must run checks outside of monitoring. We don't trust your monitoring", a senior manager said to us (we shall ceall him, Ivan .. which, ironically, was his actual name. You know who you are, Ivan!). "We like it when your hands are on the keyboard running special commands that you know or making sure the systems are ready for use. Also, we want you produce a report every morning which says you've checked out the systems," 

Ivan then added, and this is was the key to a happy life, "Well, I suppose you *could* automate it, but it must be explicit tests on the infrastructure. I mean executed checks prior to the start of 'open'. We need to excercise the dependent systems the business relies on."

And that is what made the lightbulb go off over my head: *we don't need to be there, we just need to automate what we would do if we were!*

24 hours later we wrote a script to call a bunch of scripts. Each independently ran a checks for a particular category of infrastrure like network, storage, compute, database. Because it was such a simple framework, we found that each member of the sysadmin group was happily contributing to the checks -- even those who were less development savvy (they couldn't write Perl, for example, but they could whip out a shell script with a set of commands to check something).

Very quickly we had gone from zero checks and all passive monitoring (on a very old monitoring system that doesn't exist anymore) to hundreds, then thousands. All executed within a few minutes. We had hundreds of storage arrays, and so by writing a few scriptlets, a few lines of execution logic each, that alone gave us thousands of checks being run in parallel at the start of the day, and generated an organized report each time we could have automatically sent to the head of trading. Infrastructure team could tell the business with confidence that the shop was open for business. These were a bit heavy tests, by the way, and ones we would only need to run once a day to ensure that our systems wouldn't have an issue near the peak times - market open, and right before market close.

At the time, due mostly to some geekery, we named this sort of uber-execution script `marvin`, after [Marvin the Paranoid Android](https://en.wikipedia.org/wiki/Marvin_the_Paranoid_Android), from [The Hitchhiker's Guide to the Galaxy](https://en.wikipedia.org/wiki/The_Hitchhiker%27s_Guide_to_the_Galaxy). I honestly wanted to call it "Crazy Ivan" at the time, but I figured that might get me fired. It was written in Perl (Python wasn't yet a thing at the time, this was about 20 years ago) and it was roughly the same concepts as we have above, only instead of parallel execution it was mainly sequential with some process forking. Part of the real magic was how the results were organized and reported on.

Did it cover everything? Of course not, but at the one part of the day, the one critical part the business needed to be rock solid on, we would have 100% confidence in our systems because we actually used them, actively, instead of just depending on a passive "sonar" to tell us something was amiss. Active + Passive monitoring gives you as much coverage as unit tests plus QA testing would on software. That's what `marvin` was, and that's really what `Crazy Ivan` is.

## Limitations

`Crazy Ivan` is going to lend itself at being great at checking anything you can from a command line, but at this point it's biggest limitation will be that you cannot mock user input into a web application, for example.

Additionally deployment of `Crazy Ivan` will be by a container or directly onto a machine. For some this will be a challenge, given the distributed world moving into Kubernetes and all it's ecosystem as a way of deploying apps.

> :no_entry: WARNING: `Crazy Ivan` does **NOT** want you to run it in Kubernetes, at least not if you want to use it to also check Kubernetes. Run it in a VM or possibly in the future as a Lambda Function on demand.

> :no_entry: WARNING: `Crazy Ivan` is not yet ready for consumption, it is just being built in public. Please look for a dot release to signify it's ready to test and use.

## Credits and License

Developed by Greg Gallagher (frellus), Copyright 2023 

> :information_source: Note: I credit one of my former collegues, Joel, who originally came up with the name "Marvin", for the first check framework tool. I then moved into a different job (the one with Ivan, the story above) and conceptually developed the same solution from scratch when we were given the task of running pro-active infrastructure tests. At some point I re-wrote it in Python, but became critical ifrastructure used to run thousands and thousands of checks globally. Still, I chose to name it `marvin` as a tribute to Joel, even it ended up being a *much* larger scope than the first one.

`Crazy Ivan` is the first time I am creating a `marvin` for public consumption. Other than the overall generic concept, this is a completely original work and fresh approach, as I think the problem is wide ranging, generic and timeless. None of the enterprise monitoring systems we used *in the day* survived to be still in use, and the cloud and SaaS monitoring solutions didn't exist at that time either -- but I hear some whispers that `marvin` is still in use at that place I left 10 years ago.

Regardless, I encountered a problem at just yesterday where my users were questioning if our in-house S3 object storage system was working properly. While there was monitoring, we pretty quickly pulled out the `s3cmd` command and started excercising the system, and so I realized that yet again I needed a `marvin` (and probably will again at my next job). Crazy Ivan is the final and best version of the `marvin` concept. It will likely outlive me if distributed computing is still around.


## License

This work is licensed under the MIT License, and is free to use, modify or borrow from with attribution of the author(s) as in the `LICENSE` file.

---
[^1]: The word "Ivan" was a common slang term the Americans gave to generalize Russian soldiers, as the name "Ivan" was a popular and Russian-originating first name.
[^2]: By Life of Riley - Own work, CC BY-SA 4.0, https://commons.wikimedia.org/w/index.php?curid=14055162


