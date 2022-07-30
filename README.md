# Precise3DKinematicController (2022)
A precise kinematic controller implemented in Godot but design can be applied to any physics engine. This controller defines the collision response of the body, not the motion, that is entirely up to you. The lessons I learnt building this took me to study how Valve, Nvida PhysX, and bungie do kinematic controllers. This controller is based on the Valve style. This style uses a box collision shape with manual step handling for precise control of step height. 


## Stepping behaviour
A kinematic body has a shape and is generally a box or capsule:
### Capsule
The benefit of the capsule is that the curved surface of its bottom will reflect motion up and over small steps. Any step that is less than the height of the curvature will be step-able. This means the capsule shape has built in step handling! However:
1. We cant decide how high we want steps and our stepping functionality is now strictly linked to the size of the capsule. This is not the end of the world. If you need to step over large steps use a larger capsule and make sure doors are wider to fit your character.
2. The speed at which you climb a step will be variable. A high step will slow your character more than a low step. Furthermore if your controller uses acceleration then you may only be able to climb steps at a full sprint. What happens when a player stops on the stairs then resumes from rest? Often the solution is to make the stairs so small that they will be climbed no matter the speed. (We can potentially fix this entire issue by tweaking gravity when stepping. E.g. when moving, cast the shape to check for collision and keep gravity low or removed while stepping).

### Box
Every step must be handled manually. No curvature means no reflection means no free stepping.
The solution is to warp the player to the top of the stair when detected. This however gives the issue of jerky motion which needs to be smoothed for a pleasant viewing experience.
I think this control is what makes the box shape interesting to me. Ultimately you have to ask "how important are stairs in my game?". Maybe this heuristic works: if your game environment is small; stairs are important. If your game environment is large; stairs are likely not important. For example: if your character moves around a house they will move on stairs a lot. Making sure that experience is precise might be a reason to use the box shape.

## Method
The method of achieving the stepping behaviour is to, every physics frame, cast your desired motion with an additional cast at step height. Whichever moves the furthest on the ground plane (remove step height) is the cast we use to update our character. Things are rarely this simple. We must also check before casting at step height if we are penatrating geometry. If so, we cannot step otherwise we step into the roof. We must also cast down from our step cast to find the height of the actual step. This height becomes the actual step, this prevents overstepping or stepping the max step height for every step. We must also check for slopes so we dont step on those. If all this sounds like a pain to debug: we can just use a capsule haha.


## Future:
My next plan is to get the capsule working as precisely as possible. An issue with adding manual stepping (this controller) to the capsule is that with two methods of stepping there will be inconsistancies. No, I think I will use a different approach entirely.

## Issues:
1. If I enable gravity on floors it will slide down slopes, if I disable gravity on floors it wont slide but will noisly detect floor contact. I disable gravity on floors then use a shape cast to test if Im on the floor. This is better anyway because it means small gaps in terrain wont distrupt audio or effects. 
x. there are probably more I have yet to find...