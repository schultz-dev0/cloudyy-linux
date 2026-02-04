#!/bin/bash

user=($USER)
date=($DATE)
workingdir=$(pwd)
recentdir=$(ls -Art | tail -n 1)

jokes=(
  "I told my wife she was drawing her eyebrows too high. She looked surprised."
  "Throwing acid is wrong, in my people's eyes."
  "The future, the present, and the past walked into a bar. Things got a little tense."
  "I'm reading a book on anti-gravity. It's impossible to put down."
  "I wasn't originally going to get a brain transplant, but then I changed my mind."
  "Parallel lines have so much in common. It’s a shame they’ll never meet."
  "My wife told me to stop impersonating a flamingo. I had to put my foot down."
  "I used to play piano by ear, but now I use my hands."
  "I'm on a seafood diet. I see food and I eat it."
  "I told my computer I needed a break, and now it won’t stop sending me Kit-Kats."
  "Puns about sausages are the wurst."
  "I'm afraid for the calendar. Its days are numbered."
  "I bought some shoes from a drug dealer. I don't know what he laced them with, but I've been tripping all day."
  "How do you make holy water? You boil the hell out of it."
  "I couldn't figure out how to put my seatbelt on. Then it clicked."
  "Singing in the shower is fun until you get soap in your mouth. Then it's a soap opera."
  "I used to be addicted to soap, but I'm clean now."
  "A skeleton walked into a bar and said, 'I'll have a beer and a mop.'"
  "I asked the librarian if the library had any books on paranoia. She whispered, 'They're right behind you.'"
  "I invented a new word! Plagiarism!"
  "Why don’t scientists trust atoms? Because they make up everything."
  "I was wondering why the frisbee kept getting bigger, and then it hit me."
  "I’d tell you a chemistry joke but I know I wouldn’t get a reaction."
  "The rotation of the earth really makes my day."
  "I got fired from the calendar factory. All I did was take a day off."
  "Hear about the new restaurant called Karma? There’s no menu: You get what you deserve."
  "A man walked into a bar. Ouch."
  "I broke my finger last week. On the other hand, I’m okay."
  "Someone stole my mood ring. I don't know how I feel about that."
  "The early bird might get the worm, but the second mouse gets the cheese."
  "Light travels faster than sound. That's why some people appear bright until you hear them speak."
  "I used to be a baker, but I couldn't make enough dough."
  "My boss told me to have a good day, so I went home."
  "Dogs can't operate MRI machines, but catscan."
  "I don't trust stairs. They're always up to something."
  "I threw a boomerang a few years ago. I now live in constant fear."
  "Don't trust people who do acupuncture. They're back stabbers."
  "What do you call a fake noodle? An impasta."
  "To the guy who invented zero, thanks for nothing."
  "Why did the scarecrow win an award? Because he was outstanding in his field."
  "Be careful when you follow the masses. Sometimes the 'm' is silent."
  "I poured spot remover on my dog. Now he's gone."
  "Did you hear about the mathematician who’s afraid of negative numbers? He’ll stop at nothing to avoid them."
  "Why do seagulls fly over the sea? Because if they flew over the bay, they’d be bagels."
  "A blind man walks into a bar. And a table. And a chair."
  "I have a lot of jokes about unemployed people, but none of them work."
  "I stayed up all night to see where the sun went. Then it dawned on me."
  "What’s brown and sticky? A stick."
  "I hate Russian dolls. They're so full of themselves."
  "Why don’t oysters donate to charity? Because they’re shellfish."
)

size=${#jokes[@]}
index=$(($RANDOM % $size))
# echo "${jokes[$index]}"

weather=$(~/cloudyy_scripts/get_weather.sh)
sleep 0.5
echo "Hello $USER, welcome back, here is the weather for today"
echo "$weather"
sleep 0.5
echo ""
echo ""
echo "Your most recent project was $recentdir and your current working directory is $workingdir"
echo ""
echo "Joke of the day is:"
echo "${jokes[$index]}"
