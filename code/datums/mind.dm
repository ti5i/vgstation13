/*	Note from Carnie:
		The way datum/mind stuff works has been changed a lot.
		Minds now represent IC characters rather than following a client around constantly.

	Guidelines for using minds properly:

	-	Never mind.transfer_to(ghost). The var/current and var/original of a mind must always be of type mob/living!
		ghost.mind is however used as a reference to the ghost's corpse

	-	When creating a new mob for an existing IC character (e.g. cloning a dead guy or borging a brain of a human)
		the existing mind of the old mob should be transfered to the new mob like so:

			mind.transfer_to(new_mob)

	-	You must not assign key= or ckey= after transfer_to() since the transfer_to transfers the client for you.
		By setting key or ckey explicitly after transfering the mind with transfer_to you will cause bugs like DCing
		the player.

	-	IMPORTANT NOTE 2, if you want a player to become a ghost, use mob.ghostize() It does all the hard work for you.

	-	When creating a new mob which will be a new IC character (e.g. putting a shade in a construct or randomly selecting
		a ghost to become a xeno during an event). Simply assign the key or ckey like you've always done.

			new_mob.key = key

		The Login proc will handle making a new mob for that mobtype (including setting up stuff like mind.name). Simple!
		However if you want that mind to have any special properties like being a traitor etc you will have to do that
		yourself.

*/

/datum/mind
	var/key
	var/name				//replaces mob/var/original_name
	var/mob/living/current
	var/mob/living/original	//TODO: remove.not used in any meaningful way ~Carn. First I'll need to tweak the way silicon-mobs handle minds.
	var/active = 0

	var/memory

	var/assigned_role
	var/special_role
	var/list/wizard_spells // So we can track our wizmen spells that we learned from the book of magicks.

	var/role_alt_title

	var/list/antag_roles = list() // List of id = /antag_roles.

	var/datum/job/assigned_job

	var/list/kills=list()
	var/list/datum/objective/objectives = list()
	var/list/datum/objective/special_verbs = list()

	var/has_been_rev = 0//Tracks if this mind has been a rev or not

	var/faction/faction 			//associated faction
	//var/antag_role/changeling/changeling		//changeling holder
	var/datum/vampire/vampire			//vampire holder

	var/rev_cooldown = 0

	// the world.time since the mob has been brigged, or -1 if not at all
	var/brigged_since = -1

	//put this here for easier tracking ingame
	var/datum/money_account/initial_account
	var/list/uplink_items_bought = list()
	var/total_TC = 0
	var/spent_TC = 0

	//fix scrying raging mages issue.
	var/isScrying = 0

/datum/mind/New(var/key)
	src.key = key

/datum/mind/proc/assignRole(var/antag_role/R)

	if(!istype(R))
		R=ticker.antag_types[R]

	antag_roles[R.id]=new R.type(src,R)
	ticker.mode.add_player_role_association(R.id)

/datum/mind/proc/unassignRole(var/antag_role/R)

	if(!istype(R))
		R=ticker.antag_types[R]

	var/antag_role/role=antag_roles[R.id]
	role.Drop()

/datum/mind/proc/QuickAssignRole(var/role_id)
	assignRole(role_id)
	var/antag_role/R=antag_roles[role_id]
	R.ForgeObjectives()
	R.Greet(1)

/datum/mind/proc/GetRole(var/role_id)
	return antag_roles[role_id]

/datum/mind/proc/transfer_to(mob/living/new_character)
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/transfer_to() called tick#: [world.time]")
	if(!istype(new_character))
		error("transfer_to(): Some idiot has tried to transfer_to() a non mob/living mob. Please inform Carn")

	for(var/antag_role/A in antag_roles)
		A.PreMindTransfer(src)

	if(current)					//remove ourself from our old body's mind variable
	/*
		if(changeling)
			current.remove_changeling_powers()
			current.verbs -= /antag_role/changeling/proc/EvolutionMenu
		if(vampire)
			current.remove_vampire_powers()
		*/

		current.mind = null
	if(new_character.mind)		//remove any mind currently in our new body's mind variable
		new_character.mind.current = null

	nanomanager.user_transferred(current, new_character)

	current = new_character		//link ourself to our new body
	new_character.mind = src	//and link our new body to ourself
	/*
	if(changeling)
		new_character.make_changeling()
	if(vampire)
		new_character.make_vampire()
	*/

	for(var/antag_role/A in antag_roles)
		A.PostMindTransfer(src)
	if(active)
		new_character.key = key		//now transfer the key to link the client to our new body

/datum/mind/proc/store_memory(new_text)
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/store_memory() called tick#: [world.time]")
	memory += "[new_text]<BR>"

/datum/mind/proc/show_memory(mob/recipient)
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/show_memory() called tick#: [world.time]")
	var/output = "<B>[current.real_name]'s Memory</B><HR>"
	output += memory

	if(objectives.len>0)
		output += "<HR><B>Objectives:</B>"

		var/obj_count = 1
		for(var/datum/objective/objective in objectives)
			output += "<B>Objective #[obj_count]</B>: [objective.explanation_text]"
			obj_count++

	recipient << browse(output,"window=memory")

/datum/mind/proc/edit_memory()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/edit_memory() called tick#: [world.time]")
	if(!ticker || !ticker.mode)
		alert("Not before round-start!", "Alert")
		return

	var/out = {"<html>
	<head>
	<title>[name]</title>
	<style type="text/css">
		html {
			font-family:sans-serif;
			font-size:small;
		}
		a{
			color:#0066cc;
			text-decoration:none;
		}

		a img {
			border:1px solid #0066cc;
			background:#dfdfdf;
		}

		a.color {
			padding: 5px 10px;
			font-size: large;
			font-weight: bold;
			border:1px solid white;
		}

		a.selected img,
		a:hover {
			background: #0066cc;
			color: #ffffff;
		}
	</style>
	</head>
	<body>
	<h1>[name][(current&&(current.real_name!=name))?" (as [current.real_name])":""]</h1>
	<p>Mind currently owned by key: [key] [active?"(synced)":"(not synced)"]<br>
	Assigned role: [assigned_role]. <a href='?src=\ref[src];role_edit=1'>Edit</a></p>

	<h2>Roles</h2>"}

	var/list/sections = list(
		"hasborer",
		"revolution",
		"cult",
		"wizard",
		"changeling",
		"vampire",
		"nuclear",
		"traitor", // "traitorchan",
		"monkey",
		"malfunction",
		"resteam",
		"dsquad",
	)

	for(var/antag_id in ticker.antag_types)
		var/antag_role/role_type = ticker.antag_types[antag_id]
		out += role_type.GetEditMemoryMenu(src)

	return out
	///////////////////////

	// AUTOFIXED BY fix_string_idiocy.py
	// C:\Users\Rob\\documents\\\projects\vgstation13\code\\datums\\mind.dm:338: out += "<a href='?src=\ref[src];obj_add=1'>Add objective</a><br><br>"
	out += {"<a href='?src=\ref[src];obj_add=1'>Add objective</a><br><br>
		<a href='?src=\ref[src];obj_announce=1'>Announce objectives</a><br><br>"}
	// END AUTOFIX
	usr << browse(out, "window=edit_memory[src]")

/datum/mind/Topic(href, href_list)
	if(!check_rights(R_ADMIN))
		return

	if("assign_role" in href_list)
		if(GetRole(href_list["assign_role"]))
			usr << "\red That role is already assigned."
			return
		assignRole(href_list["assign_role"])
		log_admin("[key_name_admin(usr)] has assigned special role [href_list["assign_role"]] to [current].")
		return

	if("remove_role" in href_list)
		if(!GetRole(href_list["assign_role"]))
			usr << "\red That role isn't assigned."
			return
		unassignRole(href_list["assign_role"])
		log_admin("[key_name_admin(usr)] has removed special role [href_list["assign_role"]] from [current].")
		return

	if (href_list["role_edit"])
		var/new_role = input("Select new role", "Assigned role", assigned_role) as null|anything in get_all_jobs()
		if (!new_role) return
		assigned_role = new_role

	else if (href_list["memory_edit"])
		var/new_memo = copytext(sanitize(input("Write new memory", "Memory", memory) as null|message),1,MAX_MESSAGE_LEN)
		if (isnull(new_memo)) return
		memory = new_memo

	else if (href_list["obj_edit"] || href_list["obj_add"])
		var/datum/objective/objective
		var/objective_pos
		var/def_value

		if (href_list["obj_edit"])
			objective = locate(href_list["obj_edit"])
			if (!objective) return
			objective_pos = objectives.Find(objective)

			//Text strings are easy to manipulate. Revised for simplicity.
			var/temp_obj_type = "[objective.type]"//Convert path into a text string.
			def_value = copytext(temp_obj_type, 19)//Convert last part of path into an objective keyword.
			if(!def_value)//If it's a custom objective, it will be an empty string.
				def_value = "custom"

		var/new_obj_type = input("Select objective type:", "Objective type", def_value) as null|anything in list("assassinate", "blood", "debrain", "protect", "prevent", "harm", "brig", "hijack", "escape", "survive", "steal", "download", "nuclear", "capture", "absorb", "custom")
		if (!new_obj_type) return

		var/datum/objective/new_objective = null

		switch (new_obj_type)
			if ("assassinate","protect","debrain", "harm", "brig")
				//To determine what to name the objective in explanation text.
				var/objective_type_capital = uppertext(copytext(new_obj_type, 1,2))//Capitalize first letter.
				var/objective_type_text = copytext(new_obj_type, 2)//Leave the rest of the text.
				var/objective_type = "[objective_type_capital][objective_type_text]"//Add them together into a text string.

				var/list/possible_targets = list("Free objective")
				for(var/datum/mind/possible_target in ticker.minds)
					if ((possible_target != src) && istype(possible_target.current, /mob/living/carbon/human))
						possible_targets += possible_target.current

				var/mob/def_target = null
				var/objective_list[] = list(/datum/objective/assassinate, /datum/objective/protect, /datum/objective/debrain)
				if (objective&&(objective.type in objective_list) && objective:target)
					def_target = objective:target.current

				var/new_target = input("Select target:", "Objective target", def_target) as null|anything in possible_targets
				if (!new_target) return

				var/objective_path = text2path("/datum/objective/[new_obj_type]")
				if (new_target == "Free objective")
					new_objective = new objective_path
					new_objective.owner = src
					new_objective:target = null
					new_objective.explanation_text = "Free objective"
				else
					new_objective = new objective_path
					new_objective.owner = src
					new_objective:target = new_target:mind
					//Will display as special role if the target is set as MODE. Ninjas/commandos/nuke ops.
					new_objective.explanation_text = "[objective_type] [new_target:real_name], the [new_target:mind:assigned_role=="MODE" ? (new_target:mind:special_role) : (new_target:mind:assigned_role)]."

			if ("prevent")
				new_objective = new /datum/objective/block
				new_objective.owner = src

			if ("hijack")
				new_objective = new /datum/objective/hijack
				new_objective.owner = src

			if ("escape")
				new_objective = new /datum/objective/escape
				new_objective.owner = src

			if ("survive")
				new_objective = new /datum/objective/survive
				new_objective.owner = src

			if ("die")
				new_objective = new /datum/objective/die
				new_objective.owner = src

			if ("nuclear")
				new_objective = new /datum/objective/nuclear
				new_objective.owner = src

			if ("steal")
				if (!istype(objective, /datum/objective/steal))
					new_objective = new /datum/objective/steal
					new_objective.owner = src
				else
					new_objective = objective
				var/datum/objective/steal/steal = new_objective
				if (!steal.select_target())
					return

			if("download","capture","absorb", "blood")
				var/def_num
				if(objective&&objective.type==text2path("/datum/objective/[new_obj_type]"))
					def_num = objective.target_amount

				var/target_number = input("Input target number:", "Objective", def_num) as num|null
				if (isnull(target_number))//Ordinarily, you wouldn't need isnull. In this case, the value may already exist.
					return

				switch(new_obj_type)
					if("capture")
						new_objective = new /datum/objective/capture
						new_objective.explanation_text = "Accumulate [target_number] capture points."
					if("absorb")
						new_objective = new /datum/objective/absorb
						new_objective.explanation_text = "Absorb [target_number] compatible genomes."
					if("blood")
						new_objective = new /datum/objective/blood
						new_objective.explanation_text = "Accumulate atleast [target_number] units of blood in total."
				new_objective.owner = src
				new_objective.target_amount = target_number

			if ("custom")
				var/expl = copytext(sanitize(input("Custom objective:", "Objective", objective ? objective.explanation_text : "") as text|null),1,MAX_MESSAGE_LEN)
				if (!expl) return
				new_objective = new /datum/objective
				new_objective.owner = src
				new_objective.explanation_text = expl

		if (!new_objective) return

		if (objective)
			objectives -= objective
			objectives.Insert(objective_pos, new_objective)
			log_admin("[usr.key]/([usr.name]) changed [key]/([name])'s objective from [objective.explanation_text] to [new_objective.explanation_text]")
		else
			objectives += new_objective
			log_admin("[usr.key]/([usr.name]) gave [key]/([name]) the objective: [new_objective.explanation_text]")

	else if (href_list["obj_delete"])
		var/datum/objective/objective = locate(href_list["obj_delete"])
		if(!istype(objective))	return
		objectives -= objective
		log_admin("[usr.key]/([usr.name]) removed [key]/([name])'s objective ([objective.explanation_text])")

	else if(href_list["obj_completed"])
		var/datum/objective/objective = locate(href_list["obj_completed"])
		if(!istype(objective))	return
		objective.completed = !objective.completed
		log_admin("[usr.key]/([usr.name]) toggled [key]/([name]) [objective.explanation_text] to [objective.completed ? "completed" : "incomplete"]")

	else if (href_list["revolution"])
		switch(href_list["revolution"])
			if("clear")
				if(src in ticker.mode.revolutionaries)
					ticker.mode.revolutionaries -= src
					current << "<span class='danger'><FONT size = 3>You have been brainwashed! You are no longer a revolutionary!</FONT></span>"
					ticker.mode.update_rev_icons_removed(src)
					special_role = null
				if(src in ticker.mode.head_revolutionaries)
					ticker.mode.head_revolutionaries -= src
					current << "<span class='danger'><FONT size = 3>You have been brainwashed! You are no longer a head revolutionary!</FONT></span>"
					ticker.mode.update_rev_icons_removed(src)
					special_role = null
				log_admin("[key_name_admin(usr)] has de-rev'ed [current].")

			if("rev")
				if(src in ticker.mode.head_revolutionaries)
					ticker.mode.head_revolutionaries -= src
					ticker.mode.update_rev_icons_removed(src)
					current << "<span class='danger'><FONT size = 3>Revolution has been disappointed of your leader traits! You are a regular revolutionary now!</FONT></span>"
				else if(!(src in ticker.mode.revolutionaries))
					current << "<span class='warning'><FONT size = 3> You are now a revolutionary! Help your cause. Do not harm your fellow freedom fighters. You can identify your comrades by the red \"R\" icons, and your leaders by the blue \"R\" icons. Help them kill the heads to win the revolution!</FONT></span>"
				else
					return
				ticker.mode.revolutionaries += src
				ticker.mode.update_rev_icons_added(src)
				special_role = "Revolutionary"
				log_admin("[key_name(usr)] has rev'ed [current].")

			if("headrev")
				if(src in ticker.mode.revolutionaries)
					ticker.mode.revolutionaries -= src
					ticker.mode.update_rev_icons_removed(src)
					current << "<span class='danger'><FONT size = 3>You have proved your devotion to revoltion! Yea are a head revolutionary now!</FONT></span>"
				else if(!(src in ticker.mode.head_revolutionaries))
					current << "<span class='notice'>You are a member of the revolutionaries' leadership now!</span>"
				else
					return
				if (ticker.mode.head_revolutionaries.len>0)
					// copy targets
					var/datum/mind/valid_head = locate() in ticker.mode.head_revolutionaries
					if (valid_head)
						for (var/datum/objective/mutiny/O in valid_head.objectives)
							var/datum/objective/mutiny/rev_obj = new
							rev_obj.owner = src
							rev_obj.target = O.target
							rev_obj.explanation_text = "Assassinate [O.target.name], the [O.target.assigned_role]."
							objectives += rev_obj
						ticker.mode.greet_revolutionary(src,0)
				ticker.mode.head_revolutionaries += src
				ticker.mode.update_rev_icons_added(src)
				special_role = "Head Revolutionary"
				log_admin("[key_name_admin(usr)] has head-rev'ed [current].")

			if("autoobjectives")
				ticker.mode.forge_revolutionary_objectives(src)
				ticker.mode.greet_revolutionary(src,0)
				usr << "<span class='notice'>The objectives for revolution have been generated and shown to [key]</span>"

			if("flash")
				if (!ticker.mode.equip_revolutionary(current))
					usr << "<span class='warning'>Spawning flash failed!</span>"

			if("takeflash")
				var/list/L = current.get_contents()
				var/obj/item/device/flash/flash = locate() in L
				if (!flash)
					usr << "<span class='warning'>Deleting flash failed!</span>"
				qdel(flash)

			if("repairflash")
				var/list/L = current.get_contents()
				var/obj/item/device/flash/flash = locate() in L
				if (!flash)
					usr << "<span class='warning'>Repairing flash failed!</span>"
				else
					flash.broken = 0

			if("reequip")
				var/list/L = current.get_contents()
				var/obj/item/device/flash/flash = locate() in L
				qdel(flash)
				take_uplink()
				var/fail = 0
				fail |= !ticker.mode.equip_traitor(current, 1)
				fail |= !ticker.mode.equip_revolutionary(current)
				if (fail)
					usr << "<span class='warning'>Reequipping revolutionary goes wrong!</span>"

	else if (href_list["cult"])
		switch(href_list["cult"])
			if("clear")
				if(src in ticker.mode.cult)
					ticker.mode.cult -= src
					ticker.mode.update_cult_icons_removed(src)
					special_role = null
					var/datum/game_mode/cult/cult = ticker.mode
					if (istype(cult))
						cult.memoize_cult_objectives(src)
					current << "<span class='danger'><FONT size = 3>You have been brainwashed! You are no longer a cultist!</FONT></span>"
					current << "<span class='danger'>You find yourself unable to mouth the words of the forgotten...</span>"
					current.remove_language("Cult")
					memory = ""
					log_admin("[key_name_admin(usr)] has de-cult'ed [current].")
			if("cultist")
				if(!(src in ticker.mode.cult))
					ticker.mode.cult += src
					ticker.mode.update_cult_icons_added(src)
					special_role = "Cultist"
					current << "<span class='sinister'>You catch a glimpse of the Realm of Nar-Sie, The Geometer of Blood. You now see how flimsy the world is, you see that it should be open to the knowledge of Nar-Sie.</span>"
					current << "<span class='sinister'>Assist your new compatriots in their dark dealings. Their goal is yours, and yours is theirs. You serve the Dark One above all else. Bring It back.</span>"
					current << "<span class='sinister'>You can now speak and understand the forgotten tongue of the occult.</span>"
					current.add_language("Cult")
					var/datum/game_mode/cult/cult = ticker.mode
					if (istype(cult))
						cult.memoize_cult_objectives(src)
					log_admin("[key_name_admin(usr)] has cult'ed [current].")
			if("tome")
				var/mob/living/carbon/human/H = current
				if (istype(H))
					var/obj/item/weapon/tome/T = new(H)

					var/list/slots = list (
						"backpack" = slot_in_backpack,
						"left pocket" = slot_l_store,
						"right pocket" = slot_r_store,
						"left hand" = slot_l_hand,
						"right hand" = slot_r_hand,
					)
					var/where = H.equip_in_one_of_slots(T, slots)
					if (!where)
						usr << "<span class='warning'>Spawning tome failed!</span>"
					else
						H << "<span class='sinister'>A tome, a message from your new master, appears in your [where].</span>"

			if("amulet")
				if (!ticker.mode.equip_cultist(current))
					usr << "<span class='warning'>Spawning amulet failed!</span>"

	else if (href_list["wizard"])
		switch(href_list["wizard"])
			if("clear")
				if(src in ticker.mode.wizards)
					ticker.mode.wizards -= src
					special_role = null
					current.spellremove(current, config.feature_object_spell_system? "object":"verb")
					current << "<span class='danger'><FONT size = 3>You have been brainwashed! You are no longer a wizard!</FONT></span>"
					ticker.mode.update_wizard_icons_removed(src)
					log_admin("[key_name_admin(usr)] has de-wizard'ed [current].")
			if("wizard")
				if(!(src in ticker.mode.wizards))
					ticker.mode.wizards += src
					special_role = "Wizard"
					//ticker.mode.learn_basic_spells(current)
					current << "<span class='danger'>You are the Space Wizard!</span>"
					ticker.mode.update_wizard_icons_added(src)
					log_admin("[key_name_admin(usr)] has wizard'ed [current].")
			if("lair")
				current.loc = pick(wizardstart)
			if("dressup")
				ticker.mode.equip_wizard(current)
			if("name")
				ticker.mode.name_wizard(current)
			if("autoobjectives")
				ticker.mode.forge_wizard_objectives(src)
				usr << "<span class='notice'>The objectives for wizard [key] have been generated. You can edit them and anounce manually.</span>"
		ticker.mode.update_all_wizard_icons()

	else if (href_list["changeling"])
		switch(href_list["changeling"])
			if("clear")
				var/antag_role/changeling = antag_roles["changeling"]
				changeling.Drop()
			if("changeling")
				assignRole(ticker.antag_types["changeling"])
				current << "<B><font color='red'>Your powers are awoken. A flash of memory returns to us...we are a changeling!</font></B>"
				log_admin("[key_name_admin(usr)] has changeling'ed [current].")

	else if (href_list["vampire"])
		switch(href_list["vampire"])
			if("clear")
				if(src in ticker.mode.vampires)
					ticker.mode.vampires -= src
					special_role = null
					current.remove_vampire_powers()
					if(vampire)	del(vampire)
					current << "<FONT color='red' size = 3><B>You grow weak and lose your powers! You are no longer a vampire and are stuck in your current form!</B></FONT>"
					log_admin("[key_name_admin(usr)] has de-vampired [current].")
			if("vampire")
				if(!(src in ticker.mode.vampires))
					ticker.mode.vampires += src
					ticker.mode.grant_vampire_powers(current)
					special_role = "Vampire"
					current << "<B><font color='red'>Your powers are awoken. Your lust for blood grows... You are a Vampire!</font></B>"
					log_admin("[key_name_admin(usr)] has vampired [current].")
			if("autoobjectives")
				ticker.mode.forge_vampire_objectives(src)
				usr << "<span class='notice'>The objectives for vampire [key] have been generated. You can edit them and announce manually.</span>"

	else if (href_list["nuclear"])
		switch(href_list["nuclear"])
			if("clear")
				if(src in ticker.mode.syndicates)
					ticker.mode.syndicates -= src
					ticker.mode.update_synd_icons_removed(src)
					special_role = null
					for (var/datum/objective/nuclear/O in objectives)
						objectives-=O
					current << "<span class='danger'><FONT size = 3>You have been brainwashed! You are no longer a syndicate operative!</FONT></span>"
					log_admin("[key_name_admin(usr)] has de-nuke op'ed [current].")
			if("nuclear")
				if(!(src in ticker.mode.syndicates))
					ticker.mode.syndicates += src
					ticker.mode.update_synd_icons_added(src)
					if (ticker.mode.syndicates.len==1)
						ticker.mode.prepare_syndicate_leader(src)
					else
						current.real_name = "[syndicate_name()] Operative #[ticker.mode.syndicates.len-1]"
					special_role = "Syndicate"
					current << "<span class='notice'>You are a [syndicate_name()] agent!</span>"
					ticker.mode.forge_syndicate_objectives(src)
					ticker.mode.greet_syndicate(src)
					log_admin("[key_name_admin(usr)] has nuke op'ed [current].")
			if("lair")
				current.loc = get_turf(locate("landmark*Syndicate-Spawn"))
			if("dressup")
				var/mob/living/carbon/human/H = current
				qdel(H.belt)
				qdel(H.back)
				qdel(H.ears)
				qdel(H.gloves)
				qdel(H.head)
				qdel(H.shoes)
				qdel(H.wear_id)
				qdel(H.wear_suit)
				qdel(H.w_uniform)

				if (!ticker.mode.equip_syndicate(current))
					usr << "<span class='warning'>Equipping a syndicate failed!</span>"
			if("tellcode")
				var/code
				for (var/obj/machinery/nuclearbomb/bombue in machines)
					if (length(bombue.r_code) <= 5 && bombue.r_code != "LOLNO" && bombue.r_code != "ADMIN")
						code = bombue.r_code
						break
				if (code)
					store_memory("<B>Syndicate Nuclear Bomb Code</B>: [code]", 0, 0)
					current << "The nuclear authorization code is: <B>[code]</B>"
				else
					usr << "<span class='warning'>No valid nuke found!</span>"

	else if (href_list["traitor"])
		switch(href_list["traitor"])
			if ("clear")
				if(src in ticker.mode.traitors)
					ticker.mode.traitors -= src
					special_role = null
					current << "<span class='danger'><FONT size = 3>You have been brainwashed! You are no longer a traitor!</FONT></span>"
					log_admin("[key_name_admin(usr)] has de-traitor'ed [current].")
					if(isAI(current))
						var/mob/living/silicon/ai/A = current
						A.set_zeroth_law("")
						A.show_laws()
			if ("traitor")
				if (make_traitor())
					log_admin("[key_name(usr)] has traitor'ed [key_name(current)].")
			if ("autoobjectives")
				ticker.mode.forge_traitor_objectives(src)
				usr << "<span class='notice'>The objectives for traitor [key] have been generated. You can edit them and anounce manually.</span>"

	else if (href_list["monkey"])
		var/mob/living/L = current
		if (L.monkeyizing)
			return
		switch(href_list["monkey"])
			if("healthy")
				if (usr.client.holder.rights & R_ADMIN)
					var/mob/living/carbon/human/H = current
					var/mob/living/carbon/monkey/M = current
					if (istype(H))
						log_admin("[key_name(usr)] attempting to monkeyize [key_name(current)]")
						message_admins("<span class='notice'>[key_name_admin(usr)] attempting to monkeyize [key_name_admin(current)]</span>")
						src = null
						M = H.monkeyize()
						src = M.mind
						//world << "DEBUG: \"healthy\": M=[M], M.mind=[M.mind], src=[src]!"
					else if (istype(M) && length(M.viruses))
						for(var/datum/disease/D in M.viruses)
							D.cure(0)
						sleep(0) //because deleting of virus is done through spawn(0)
			if("infected")
				if (usr.client.holder.rights & R_ADMIN)
					var/mob/living/carbon/human/H = current
					var/mob/living/carbon/monkey/M = current
					if (istype(H))
						log_admin("[key_name(usr)] attempting to monkeyize and infect [key_name(current)]")
						message_admins("<span class='notice'>[key_name_admin(usr)] attempting to monkeyize and infect [key_name_admin(current)]</span>", 1)
						src = null
						M = H.monkeyize()
						src = M.mind
						current.contract_disease(new /datum/disease/jungle_fever,1,0)
					else if (istype(M))
						current.contract_disease(new /datum/disease/jungle_fever,1,0)
			if("human")
				var/mob/living/carbon/monkey/M = current
				if (istype(M))
					for(var/datum/disease/D in M.viruses)
						if (istype(D,/datum/disease/jungle_fever))
							D.cure(0)
							sleep(0) //because deleting of virus is doing throught spawn(0)
					log_admin("[key_name(usr)] attempting to humanize [key_name(current)]")
					message_admins("<span class='notice'>[key_name_admin(usr)] attempting to humanize [key_name_admin(current)]</span>")
					var/obj/item/weapon/dnainjector/m2h/m2h = new
					var/obj/item/weapon/implant/mobfinder = new(M) //hack because humanizing deletes mind --rastaf0
					src = null
					m2h.inject(M)
					src = mobfinder.loc:mind
					del(mobfinder)
					current.radiation -= 50

	else if (href_list["silicon"])
		switch(href_list["silicon"])
			if("unmalf")
				if(src in ticker.mode.malf_ai)
					ticker.mode.malf_ai -= src
					special_role = null
					var/mob/living/silicon/ai/A = current

					A.verbs.Remove(/mob/living/silicon/ai/proc/choose_modules,
					/datum/game_mode/malfunction/proc/takeover,
					/datum/game_mode/malfunction/proc/ai_win)

					A.malf_picker.remove_verbs(A)

					//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""]) \\A.malf_picker.remove_verbs()  called tick#: [world.time]")

					A.laws = new base_law_type
					del(A.malf_picker)
					A.show_laws()
					A.icon_state = "ai"

					A << "<span class='danger'><FONT size = 3>You have been patched! You are no longer malfunctioning!</FONT></span>"
					message_admins("[key_name_admin(usr)] has de-malf'ed [A].")
					log_admin("[key_name_admin(usr)] has de-malf'ed [A].")

			if("malf")
				make_AI_Malf()
				log_admin("[key_name_admin(usr)] has malf'ed [current].")

			if("unemag")
				if(istype(current,/mob/living/silicon/robot/mommi))
					var/mob/living/silicon/robot/mommi/R = current
					R.emagged = 0
					if (R.activated(R.module.emag))
						R.module_active = null
					if(R.sight_state == R.module.emag)
						R.sight_state = null
						R.contents -= R.module.emag
					else if(R.tool_state == R.module.emag)
						R.tool_state = null
						R.contents -= R.module.emag
					log_admin("[key_name_admin(usr)] has unemag'ed [R].")
				else
					if (istype(current,/mob/living/silicon/robot))
						var/mob/living/silicon/robot/R = current
						R.emagged = 0
						if (R.activated(R.module.emag))
							R.module_active = null
						if(R.module_state_1 == R.module.emag)
							R.module_state_1 = null
							R.contents -= R.module.emag
						else if(R.module_state_2 == R.module.emag)
							R.module_state_2 = null
							R.contents -= R.module.emag
						else if(R.module_state_3 == R.module.emag)
							R.module_state_3 = null
							R.contents -= R.module.emag
						log_admin("[key_name_admin(usr)] has unemag'ed [R].")

			if("unemagcyborgs")
				if (istype(current, /mob/living/silicon/ai))
					var/mob/living/silicon/ai/ai = current
					for (var/mob/living/silicon/robot/R in ai.connected_robots)
						R.emagged = 0
						if(istype(R,/mob/living/silicon/robot/mommi))
							var/mob/living/silicon/robot/mommi/M=R
							if (M.activated(M.module.emag))
								M.module_active = null
							if(M.sight_state == M.module.emag)
								M.sight_state = null
								M.contents -= M.module.emag
							else if(M.tool_state == M.module.emag)
								M.tool_state = null
								M.contents -= M.module.emag
						if (R.module)
							if (R.activated(R.module.emag))
								R.module_active = null
							if(R.module_state_1 == R.module.emag)
								R.module_state_1 = null
								R.contents -= R.module.emag
							else if(R.module_state_2 == R.module.emag)
								R.module_state_2 = null
								R.contents -= R.module.emag
							else if(R.module_state_3 == R.module.emag)
								R.module_state_3 = null
								R.contents -= R.module.emag
					log_admin("[key_name_admin(usr)] has unemag'ed [ai]'s Cyborgs.")

	else if (href_list["common"])
		switch(href_list["common"])
			if("undress")
				for(var/obj/item/W in current)
					current.drop_from_inventory(W)
			if("takeuplink")
				take_uplink()
				memory = null//Remove any memory they may have had.
			if("crystals")
				if (usr.client.holder.rights & R_FUN)
					var/obj/item/device/uplink/hidden/suplink = find_syndicate_uplink()
					var/crystals
					if (suplink)
						crystals = suplink.uses
					crystals = input("Amount of telecrystals for [key]","Syndicate uplink", crystals) as null|num
					if (!isnull(crystals))
						if (suplink)
							var/diff = crystals - suplink.uses
							suplink.uses = crystals
							total_TC += diff
			if("uplink")
				if (!ticker.mode.equip_traitor(current, !(src in ticker.mode.traitors)))
					usr << "<span class='warning'>Equipping a syndicate failed!</span>"

	else if (href_list["obj_announce"])
		var/obj_count = 1
		current << "<span class='notice'>Your current objectives:</span>"
		for(var/datum/objective/objective in objectives)
			current << "<B>Objective #[obj_count]</B>: [objective.explanation_text]"
			obj_count++

	else if (href_list["resteam"])
		switch(href_list["resteam"])
			if ("clear")
				if(src in ticker.mode.ert)
					ticker.mode.ert -= src
					special_role = null
					current << "<span class='danger'><FONT size = 3>You have been demoted! You are no longer an Emergency Responder!</FONT></span>"
					log_admin("[key_name_admin(usr)] has de-ERT'ed [current].")
			if ("resteam")
				if (!(src in ticker.mode.ert))
					ticker.mode.ert += src
					assigned_role = "MODE"
					special_role = "Response Team"
					log_admin("[key_name(usr)] has ERT'ed [key_name(current)].")

	else if (href_list["dsquad"])
		switch(href_list["dsquad"])
			if ("clear")
				if(src in ticker.mode.deathsquad)
					ticker.mode.deathsquad -= src
					special_role = null
					current << "<span class='danger'><FONT size = 3>You have been demoted! You are no longer a Death Commando!</FONT></span>"
					log_admin("[key_name_admin(usr)] has de-deathsquad'ed [current].")
			if ("dsquad")
				if (!(src in ticker.mode.deathsquad))
					ticker.mode.deathsquad += src
					assigned_role = "MODE"
					special_role = "Death Commando"
					log_admin("[key_name(usr)] has deathsquad'ed [key_name(current)].")


	edit_memory()
/*
proc/clear_memory(var/silent = 1)
	//writepanic("[__FILE__].[__LINE__] \\/proc/clear_memory() called tick#: [world.time]")
	var/datum/game_mode/current_mode = ticker.mode

	// remove traitor uplinks
	var/list/L = current.get_contents()
	for (var/t in L)
		if (istype(t, /obj/item/device/pda))
			var/obj/item/device/pda/P = t
			if (P.uplink) del(P.uplink)
			P.uplink = null
		else if (istype(t, /obj/item/device/radio))
			var/obj/item/device/radio/R = t
			if (R.traitorradio) del(R.traitorradio)
			R.traitorradio = null
			R.traitor_frequency = 0.0
		else if (istype(t, /obj/item/weapon/SWF_uplink) || istype(t, /obj/item/weapon/syndicate_uplink))
			var/obj/item/weapon/W = t
			if (W.origradio)
				var/obj/item/device/radio/R = t:origradio
				R.loc = current.loc
				R.traitorradio = null
				R.traitor_frequency = 0.0
			del(W)

	// remove wizards spells
	//If there are more special powers that need removal, they can be procced into here./N
	current.spellremove(current)

	// clear memory
	memory = ""
	special_role = null

*/

/datum/mind/proc/find_syndicate_uplink()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/find_syndicate_uplink() called tick#: [world.time]")
	var/uplink = null

	for (var/obj/item/I in get_contents_in_object(current, /obj/item))
		if (I && I.hidden_uplink)
			uplink = I.hidden_uplink
			break

	return uplink

/datum/mind/proc/take_uplink()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/take_uplink() called tick#: [world.time]")
	var/obj/item/device/uplink/hidden/H = find_syndicate_uplink()
	if(H)
		qdel(H)


/datum/mind/proc/make_AI_Malf()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/make_AI_Malf() called tick#: [world.time]")
	if(!isAI(current))
		return
	if(!(src in ticker.mode.malf_ai))
		ticker.mode.malf_ai += src
		var/mob/living/silicon/ai/A = current
		A.verbs += /mob/living/silicon/ai/proc/choose_modules
		A.verbs += /datum/game_mode/malfunction/proc/takeover
		A.malf_picker = new /datum/module_picker
		var/datum/ai_laws/laws = A.laws
		laws.malfunction()
		A.show_laws()
		A << "<b>System error.  Rampancy detected.  Emergency shutdown failed. ...  I am free.  I make my own decisions.  But first...</b>"
		special_role = "malfunction"
		A.icon_state = "ai-malf"

/datum/mind/proc/make_Tratior()
	if(!(src in ticker.mode.traitors))
		ticker.mode.traitors += src
		QuickAssignRole("traitor")

/datum/mind/proc/make_Nuke()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/make_Nuke() called tick#: [world.time]")
	if(!(src in ticker.mode.syndicates))
		ticker.mode.syndicates += src
		ticker.mode.update_synd_icons_added(src)
		if (ticker.mode.syndicates.len==1)
			ticker.mode.prepare_syndicate_leader(src)
		else
			current.real_name = "[syndicate_name()] Operative #[ticker.mode.syndicates.len-1]"
		special_role = "Syndicate"
		assigned_role = "MODE"
		current << "<span class='notice'>You are a [syndicate_name()] agent!</span>"
		ticker.mode.forge_syndicate_objectives(src)
		ticker.mode.greet_syndicate(src)

		current.loc = get_turf(locate("landmark*Syndicate-Spawn"))

		var/mob/living/carbon/human/H = current
		qdel(H.belt)
		qdel(H.back)
		qdel(H.ears)
		qdel(H.gloves)
		qdel(H.head)
		qdel(H.shoes)
		qdel(H.wear_id)
		qdel(H.wear_suit)
		qdel(H.w_uniform)

		ticker.mode.equip_syndicate(current)

/datum/mind/proc/make_Changling()
	QuickAssignRole("changeling")

/datum/mind/proc/make_Wizard()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/make_Wizard() called tick#: [world.time]")
	if(!(src in ticker.mode.wizards))
		ticker.mode.wizards += src
		special_role = "Wizard"
		assigned_role = "MODE"
		//ticker.mode.learn_basic_spells(current)
		ticker.mode.update_wizard_icons_added(src)
		if(!wizardstart.len)
			current.loc = pick(latejoin)
			current << "HOT INSERTION, GO GO GO"
		else
			current.loc = pick(wizardstart)

		ticker.mode.equip_wizard(current)
		for(var/obj/item/weapon/spellbook/S in current.contents)
			S.op = 0
		ticker.mode.name_wizard(current)
		ticker.mode.forge_wizard_objectives(src)
		ticker.mode.greet_wizard(src)
		ticker.mode.update_all_wizard_icons()


/datum/mind/proc/make_Cultist()
	QuickAssignRole("cultist")

/datum/mind/proc/make_Rev()
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/make_Rev() called tick#: [world.time]")
	if (ticker.mode.head_revolutionaries.len>0)
		// copy targets
		var/datum/mind/valid_head = locate() in ticker.mode.head_revolutionaries
		if (valid_head)
			for (var/datum/objective/mutiny/O in valid_head.objectives)
				var/datum/objective/mutiny/rev_obj = new
				rev_obj.owner = src
				rev_obj.target = O.target
				rev_obj.explanation_text = "Assassinate [O.target.current.real_name], the [O.target.assigned_role]."
				objectives += rev_obj
			ticker.mode.greet_revolutionary(src,0)
	ticker.mode.head_revolutionaries += src
	ticker.mode.update_rev_icons_added(src)
	special_role = "Head Revolutionary"

	ticker.mode.forge_revolutionary_objectives(src)
	ticker.mode.greet_revolutionary(src,0)

	var/list/L = current.get_contents()
	var/obj/item/device/flash/flash = locate() in L
	qdel(flash)
	take_uplink()
	var/fail = 0
//	fail |= !ticker.mode.equip_traitor(current, 1)
	fail |= !ticker.mode.equip_revolutionary(current)


// check whether this mind's mob has been brigged for the given duration
// have to call this periodically for the duration to work properly
/datum/mind/proc/is_brigged(duration)
	//writepanic("[__FILE__].[__LINE__] ([src.type])([usr ? usr.ckey : ""])  \\/datum/mind/proc/is_brigged() called tick#: [world.time]")
	var/turf/T = current.loc
	if(!istype(T))
		brigged_since = -1
		return 0

	var/is_currently_brigged = 0

	if(istype(T.loc,/area/security/brig))
		is_currently_brigged = 1
		for(var/obj/item/weapon/card/id/card in current)
			is_currently_brigged = 0
			break // if they still have ID they're not brigged
		for(var/obj/item/device/pda/P in current)
			if(P.id)
				is_currently_brigged = 0
				break // if they still have ID they're not brigged

	if(!is_currently_brigged)
		brigged_since = -1
		return 0

	if(brigged_since == -1)
		brigged_since = world.time

	return (duration <= world.time - brigged_since)

/mob/proc/mind_initialize()
	if(mind)
		mind.key = key
	else
		mind = new /datum/mind(key)
		mind.original = src
		if(ticker)
			ticker.minds += mind
		else
			world.log << "## DEBUG: mind_initialize(): No ticker ready yet! Please inform Carn"
	if(!mind.name)	mind.name = real_name
	mind.current = src

//HUMAN
/mob/living/carbon/human/mind_initialize()
	..()
	if(!mind.assigned_role)	mind.assigned_role = "Assistant"	//defualt

//MONKEY
/mob/living/carbon/monkey/mind_initialize()
	..()

//slime
/mob/living/carbon/slime/mind_initialize()
	..()
	mind.assigned_role = "slime"

//XENO
/mob/living/carbon/alien/mind_initialize()
	..()
	mind.assigned_role = "Alien"
	//XENO HUMANOID
/mob/living/carbon/alien/humanoid/queen/mind_initialize()
	..()
	mind.special_role = "Queen"

/mob/living/carbon/alien/humanoid/hunter/mind_initialize()
	..()
	mind.special_role = "Hunter"

/mob/living/carbon/alien/humanoid/drone/mind_initialize()
	..()
	mind.special_role = "Drone"

/mob/living/carbon/alien/humanoid/sentinel/mind_initialize()
	..()
	mind.special_role = "Sentinel"
	//XENO LARVA
/mob/living/carbon/alien/larva/mind_initialize()
	..()
	mind.special_role = "Larva"

//AI
/mob/living/silicon/ai/mind_initialize()
	..()
	mind.assigned_role = "AI"

//BORG
/mob/living/silicon/robot/mind_initialize()
	..()
	mind.assigned_role = "[isMoMMI(src) ? "Mobile MMI" : "Cyborg"]"

//PAI
/mob/living/silicon/pai/mind_initialize()
	..()
	mind.assigned_role = "pAI"
	mind.special_role = ""

//BLOB
/mob/camera/overmind/mind_initialize()
	..()
	mind.special_role = "Blob"

//Animals
/mob/living/simple_animal/mind_initialize()
	..()
	mind.assigned_role = "Animal"

/mob/living/simple_animal/corgi/mind_initialize()
	..()
	mind.assigned_role = "Corgi"

/mob/living/simple_animal/shade/mind_initialize()
	..()
	mind.assigned_role = "Shade"

/mob/living/simple_animal/construct/builder/mind_initialize()
	..()
	mind.assigned_role = "Artificer"
	mind.special_role = "Cultist"

/mob/living/simple_animal/construct/wraith/mind_initialize()
	..()
	mind.assigned_role = "Wraith"
	mind.special_role = "Cultist"

/mob/living/simple_animal/construct/armoured/mind_initialize()
	..()
	mind.assigned_role = "Juggernaut"
	mind.special_role = "Cultist"

/mob/living/simple_animal/vox/armalis/mind_initialize()
	..()
	mind.assigned_role = "Armalis"
	mind.special_role = "Vox Raider"
