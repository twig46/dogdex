# DogDex
![DogDex Hackatime](https://hackatime-badge.hackclub.com/U09AR4BDCGZ/dogdex) ![dog_nn Hackatime](https://hackatime-badge.hackclub.com/U09AR4BDCGZ/dog_nn)

A real life Pokédex.. but for dogs!

## Overview

I'm making this [project](https://flavortown.hackclub.com/projects/11999) for the [2026 Hack Club Flavortown event](https://flavortown.hackclub.com/), I am also submitting it in the [2026 STAV Science Talent Search](https://stav.org.au/science-talent-search/).

The main two features of DogDex are tracking, and identifying dogs. By going to the little camera icon in the top right you can either take a photo of a dog or use one in your library.

![camera](img/camera.png)

Your picture is then sent to my personal API for identifying dogs and a result is spit out.

![result](img/result.png)

You can then press "Ok" to add the dog to your personal collection!

### Extra Usage Notes
 - Pressing the unfilled circle on the top bar brings up a bunch more dogs on the collection screen, but most of them won't have any information
 - If you re-open the app too many times or process too many dogs you will get rate limited but you would have to be actively trying to reach the limit

## Design Process

 - The first step of the process was obviously getting a neural network that could identify dogs, at first I used [this](https://www.kaggle.com/datasets/jessicali9530/stanford-dogs-dataset) dataset, but much later in development I switched to [this](https://hyper.ai/en/datasets/16786) one
 - After I got a basic [neural network](https://github.com/twig46/dog_nn) working I needed a frontend. After about 5 minutes of deliberation I decided on [Flutter](https://flutter.dev/). Although I had never used Flutter or Dart previously I decided it was perfect for the job and I got busy working
 - At first I wanted to intergrate the neural network straight into the app (mostly because I didn't want to set up an API). This ended up failing miserably so I conceded and ended up making a backend (closed-source for the foreseeable future)
 - I made the backend in Python using [FastAPI](https://github.com/fastapi/fastapi) and I orginally hosted it on [Render](https://render.com/). Eventually I switched from Render to [Railway](https://railway.com/) due to Render's incredibly slow "spin up" times. I then also eventually switched from Railway to running it locally due to my discovery of Railway's "[credits](https://docs.railway.com/pricing/plans)" system
 - From this point most development was on making the API more safe, making the UI more intuitive and closer to my vision and training the neural network for better results
 - I am currently working on the "Dog Info" section of the app as well as making it run on web for a cleaner demo experience

## Download
You can download the latest build of the Android app from https://tobyv.dev/dogdex/dogdex.apk (direct download warning).
I currently have little to no plans for a PC or iOS port however I may consider it if demand is high enough (unlikely).

## Contact
If you have any issues or suggestions please contect me either at [support@tobyv.dev](mailto:support@tobyv.dev) or [submit an issue](https://github.com/twig46/dogdex/issues/new/choose) on the GitHub repo.
