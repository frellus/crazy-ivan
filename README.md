# Crazy Ivan - Completely Paranoid and Crazy Monitoring

## Overview

The concept of "Observability" for services and systems is prevalent, and there are many excellent systems and frameworks designed for monitoring infrastructure and services. All of them rely on "passive" monitoring, however - metrics and logs are gathered and correlated looking for exceptions. No exceptions, no issues, right?

Except when a system is alive (as far as the monitoring sees) but is otherwise unresponsive in it's primary duty or with service times which fall out of SLA/SLO bounds, it is often difficult to raise awareness. The best, most monitored systems in the world still managed to get noticed by users as the catch-all monitoring. That's because users are actually *using* the system, actively.

This is the difference between "active" and "passive" monitoring. One actively excercises the service and experiences a loss, whereas "passive" monitoring tries to capture the same, ideally proactively, of a potential service outage.

### So What is Crazy Ivan?

Crazy Ivan is designed to be an execution engine for paranoid, active service checks. The design goals are simple:

* execute active service checks on a defined periodic basis
* extremely extensible - *tests can be written in any language so long as their output conforms to what Crazy Ivan needs*
* highly resiliant with few external dependencies - *everything is self-contained to lower the risk of a dependent piece of infrastructure causing an outage*
* higly parallelized - *a failing or hung check doesn't cause the risk other checks being run*

### OK, Why is it called "Crazy Ivan"?

The phrase "Crazy Ivan"[^1] was a cold war term which originated from a manuver the Soviet submarines would do to "clear their baffles". Baffles refers to the blind spot behind submarines traditionally not covered by sonar.

<img src="crazy_ivan/priv/images/480px-Submarine_baffles.png" alt="A submarine's baffle space" width="25%" height="25%"/>[^2]

Soviet subs would periodically make a sudden, hard turn to check if an enemy attack submarine was stalking it from behind, a favorable firing position for any hunter (see [Wikipedia entry on baffles](https://en.wikipedia.org/wiki/Baffles_(submarine))). The American submarines could only go undetected by shutting off their engines and "going quiet" by drifting, which posed a huge risk of colliding into the forward sub. This was popularized in the 1990 [Tom Clancy](https://en.wikipedia.org/wiki/Tom_Clancy) movie, ["The Hunt for Red October"](https://en.wikipedia.org/wiki/The_Hunt_for_Red_October_(film)) which portrayed this as a paranoid move, almost like a spy afraid of his shadow. In later years it became obsolete with the additon of a towed-array sonar.

<img src="crazy_ivan/priv/images/crazy-ivan-scene.png" alt="Hunt for Red October scene" width="25%" height="25%"/>

---

## A Simple Example

Let's say you have an API service, run from an nginx server and dependent on a PostgreSQL database.

Now, you might have monitoring from the web server looking at access logs and reporting on a particular pattern. There also could be prometheus metrics the webserver returns showing it's alive, how much activity it has had in terms of operations, same for the database. accordion

A "Crazy Ivan" check could be written in a few lines of shell script to query the API and return results. All that is needed is some executable with arguments to be defined (i.e. that shell script), the expected service time, a timeout value (optional) and a description of the check.accordion

Shell script:
```bash
#!/bin/bash

# run against the six common API endpoints
for method in users roles inventory tasks alerts messages
    curl --fail --silent -X GET "${target}/${method}" > /dev/null
    return_code=$?
    if [ $return_code -ne 0 ]; then
        echo "%IVAN% FAIL on ${target} for method ${method}"
        exit $return_code
    fi
done

exit 0
```

Sample config file:
```yaml
---

- name: api-checks                                              # Name of this check, must be globally unique
    description: Check our API services                         # friendly description (appears in the web report)
    method:
        script: api/api-checks.sh                               # path to the script from Crazy Ivan's root (defined globally)
    targets:                                                    # target variables to be passed to the script as an environment variable, $target
        - http://api.example.com/api/v3/                   
        - http://admin.example.com/api/v2/               
        - http://old.example.com/api/v2/                   
    env:                                                        # optional list of ENVIRONMENT variables to pass to the shell environment
        api-key:       $secret(api-key)                         
        api-username:  svc-crazy-ivan                            
    slo:                                                        # Service Level Objectives
        expected: 30s                                           # time this check is expected to take
        tolerance_high: 25%                                     # latency timing can be +/- the expected slo
        timeout: 60s                                            # check should die as "failed" if this timeout is reached
    schedule:                                                   # Schedule to Run on 
        method: sequential                                      # run against all the above targets one at a time, not in parallel
        frequency:
            - random_hourly                                     # don't make the check fall on any particular exact time, run every hour +/- some mins
        except:
            - weekends                                          # don't run on the weekends
    alert: true                                                 # send an alert if this check fails
```
 The idea is to be as low overhead on writing scripts as possible so as to encourage others in our team to contribute as well. Infrastructure and services have the same challenges around testing that engineers have - you want to ensure coverage, and likewise we want to make sure our infrastructure is covered as well and not just from users.

 By writing that one "active" check logic script, and using the metalanguage in the config file, Crazy Ivan will run six checks (in this case, simple curl commands) against each of the the three urls listed as targets, sequentially about once an hour. Since each run gets six checks, we now have 18 active checks being done in our environment. If any of them should fail, the whole check for that target will fail and an alert would be generated. Any time a script or command exits with a non-zero exit code, it is assumed to be failed, and the line that echos `%IVAN%` allows us to give an explicit description of where the failure happened as a top level status (described later)
 
 Additionally you can see in the configuration file, we're also expecting an SLO of about 25ms for the checks to run in 
 Each of those targets is getting checked, and alert us if it's taking more than 25ms for any of them (+ 25% of that number, so we could go as high as 31.25ms or as low as 18ms before alerting that something is wrong. This could also be a pure multiplier on the latency).
 
 So we know inherently that we are excercising the whole chain of dependencies from API code, web server and database, as well as measuring the service time directly. Paranoid? You bet, but we want to detect issues, and using the data path that a client would use allows us to effectively do this.accordion
 
 Does Crazy Ivan replace the monitoring we have on each of those components? Not at all, but it does excercise the entire path from a client, which is a huge advantage. This is a very simple example. The tests can be run as scriptlets, similar to how you would write unit tests on code. The method of execution and the complexity, or lack of it, is entirely up to the developer or SRE.

 The other nice point about this approach is that it is designed to keep the execution part as simple as possible, and separate from the way it is being called and evaluated (as defined in the config file). Using variables and target lists we could use the same check over multiple targets as well, so for example the script could be simplified where it's passed a url and runs 10 checks on the same target, and likewise we have 100 different urls to check we've made 1000 active checks in the same

### Devloop

So our dev loop is simple!
1. write generic scriptlet (can be any generated binary or executable program, such as a Python or Golang binary, or even just a single shell command). The key is that the execution logic should be as simple as possible
   
2. give it a name and descibe it (this is how it'll appear on the dashboard, as well as how it is categorized)
   
3. define the way the check(s) should be run including:
   - targets (can also be a list of targets in a file, or database source)
   - SLO, "Service Level Objective"
   - any environment variables or special secret keys to make it run

4. commit to git repo
   
5. have a production environment that has a clone of this repo and is able to pull from main as a way of running


## Crazy Ivan's Architecture and Development Methodology

Crazy Ivan is developed in [Elixir](https://elixir-lang.org) because the [BEAM](https://en.wikipedia.org/wiki/BEAM_(Erlang_virtual_machine)), in my humble opinion, is absolutely awesome as a systems automation language with it's lightware process and concurrency model. Likewise, [Phoenix](https://www.phoenixframework.org) + [Tailwind CSS](https://tailwindcss.com) allows for creating an extremely nice, simple dashboard to display the live status of checks natively in Elixir without any real JavaScript.

The other key development aspect that [OTP](https://en.wikipedia.org/wiki/Open_Telecom_Platform) gives us is the [Actor](https://en.wikipedia.org/wiki/Actor_model) Model, which lends itself quite nicely to this problem. Each check will be a separate OTP process which is always running (most of the time idle). These processes will act as exectors to ensure the checks are being run as defined, and are being published back to the collection point. To do this, we do **NOT** need a separate message bus, as Elixir and Phoenix have this builtin, so we are keeping our Crazy Ivan environment as self-sustaining as possible. The most complicated observability platforms in the world usually depend on architectural components to run, such as Kafka, Redis or such, and in our case we do not want to have any dependencies since that is exactly what we are checking! How bad would it be if we were checking the health of a database but we depended on the database itself to run?!

For that point alone, what a blessing Elixir is: we can eliminate middleware, database, scheduler, message bus, and everything except for an execution environment to run from. To that end, it is **HIGHLY** recommended that you do not run Crazy Ivan inside of a Kubernetes, or other Container-based distributed framework.

> If you don't know about [Elixir](https://elixir-lang.org) or [Phoenix](https://www.phoenixframework.org), stop whatever you are doing and watch this talk, ["The Soul of Erlang and Elixir"](https://youtu.be/JvBT4XBdoUE) by Sasa Juric. It's what originally inspired me to start learning Elixir and about the BEAM, thinking about the implications of such capabilities with true fault tolerance and parallelism it brings.

### Backstory

Crazy Ivan came about as a project which, conceptionally, I've found myself writing in every environment I've worked in.

A few (20!) years ago, while working for a global bank and trading firm, we were challenged one day to run health check prior to the start of trading. An issue happened with the infrastructure systems causing an "outage", and unfortunately there was a small gap in our monitoring. We fixed it in that case, but the amount of flack we got was high, and the top execs demanded that IT be in the office running checks every morning before the "open" (of the markets).

"But we have monitoring going 24x7! We'll know if something is broken!" we cried, as no one in IT wanted to be up and in the office checking out storage and databases at 6:30 in the morning.

"You must run checks outside of monitoring. We don't trust your monitoring. We like it when your hands on the keyboard running commands that you know that monitoring doesn't. Also, we want you produce a report every day which says you've checked out the systems," a senior manager said (we shall call him, Ivan .. which, ironically, was his actual name. You know who you are, Ivan!). 

Ivan then added, and this is the key here, "Well, I suppose you could automated it, but it must be explicit, executed checks prior to the start of 'open'. We need to excercise the dependent systems" -- and that is what made the lightbulb go off over my head: we don't need to be there, we just need to automate what we would do.accordion

24 hours later we had checks running that each member of the sysadmin group was happily contributing to, even those who were less development savvy (they couldn't write Perl, but they could whip out a shell script with a set of commands to check something). Suddenly we went from 0 checks and all passive monitoring to hundreds. We had 100s of storage arrays, and writing a few scriptlets, a few lines of execution logic each, gave us thousands of checks being run in parallel at the start of the day where the Infrastructure team could tell the business with confidence that the shop was open for business.

At the time, we named this sort of uber-execution script "Marvin", after [Marvin the Paranoid Android](https://en.wikipedia.org/wiki/Marvin_the_Paranoid_Android), from [The Hitchhiker's Guide to the Galaxy](https://en.wikipedia.org/wiki/The_Hitchhiker%27s_Guide_to_the_Galaxy). I honestly wanted to call it "Crazy Ivan", but I figured that might get me fired. It was written in Perl (Python wasn't yet a thing at the time, this was about 20 years ago) and it was roughly the same concepts as we have above, only instead of parallel execution it was mainly sequential with some process forking. The real magic was how the results were organized and reported on.accordion

Marvin checks became the norm (I'm not sure that the code isn't still running there, to be honest), and my team - out of initial pure laziness and inability to wake up at a Trader's time of day - managed to catch *many* gaps in our passive (and extensive!) monitoring platform before users would report issues.

Did it cover everything? Of course not, but at the one part of the day, the one critical part the business needed to be rock solid on, we would have 100% confidence in our systems because we actually used them, actively, instead of just depending on "sonar". Active + Passive monitoring gives you as much coverage as unit testing plus QA testing would on a product. That's what Marvin was, and that's what Crazy Ivan is.

## Credits and License

Developed by Greg Gallagher (frellus), Copyright 2023 

### License

This work is licensed under the Apache License, and is free to use, modify or borrow from with attribution of the author(s).


---
[^1]: The word "Ivan" was a common slang term the Americans gave to generalize Russian soldiers, as the name "Ivan" was a popular and Russian-originating first name.
[^2]: By Life of Riley - Own work, CC BY-SA 4.0, https://commons.wikimedia.org/w/index.php?curid=14055162


