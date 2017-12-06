open Lymp
open Risk_state
open Command
open Board
open AI

(* change "python3" to the name of your interpreter *)
let interpreter = "python3"
let py = init ~exec:interpreter "."
let simple = get_module py "simple"
let graphics = get_module py "graphics"

(* Prints the input list*)
let rec print_list = function
  | [] -> ()
  | e::l -> Pervasives.print_int e ; Pervasives.print_string " " ; print_list l

(* Draws the board of the game*)
let board = get graphics "drawBoard" []
let dice_results = Pytuple [Pylist[Pyint 6; Pyint 5; Pyint 3];Pylist[Pyint 6; Pyint 1;]]

(* Returns tuple of matching country *)
let rec get_country_tuple occupied_countries (target: string) =
  match occupied_countries with
  |[] -> Pynone
  |(c,p,i)::t -> if c.country_id = target then (Pytuple [Pystr c.country_id;Pystr p.player_id;Pyint i]) else get_country_tuple t target

(* Convert occupied countries list to python*)
let rec occupied_countries_python occupied_countries acc =
  match occupied_countries with
  | [] -> Pylist acc
  |(c,p,i)::t -> occupied_countries_python t
                   ((Pytuple [Pystr c.country_id;Pystr p.player_id;Pyint i]) :: acc)
(* Convert card amounts to python*)
let rec card_amounts_python player_list acc =
  match player_list with
  | [] -> Pylist acc
  | h::t -> card_amounts_python t
              ((Pytuple [Pystr h.player_id; Pyint (List.length h.cards)]) :: acc)
(* Get string of the current click*)
let string_of_clicked clicked =
match clicked with
    | Pytuple [Pystr strin; Pybool b] -> strin
    | _ -> failwith "Should not be here"
(* Get boolean of the current click*)
let bool_of_clicked clicked =
match clicked with
    | Pytuple [Pystr str; Pybool b] -> b
    | _ -> failwith "Should not be here"
(* Get a click action from the user as a tuple (string,bool), with [string]
   representing the name of the country/button and bool is True if the click
   is inside of a country*)

(* Updates the graphics of board with the current click*)
let update_board_with_click the_state clicked notification=
  match clicked with
  | Pytuple [Pystr str; Pybool b] -> call graphics "updateBoard"
  [board;clicked;get_country_tuple the_state.occupied_countries str;
  card_amounts_python the_state.active_players [];Pyint the_state.reward;
   Pyint the_state.total_turns;dice_results;Pystr the_state.player_turn.player_id;
  notification];
  | _ -> failwith "Should not be here"
(* Updates the graphics of board without a click*)
let update_board_no_click the_state notification = call graphics "updateBoardNoClick"
  [board;Pynone;
   card_amounts_python the_state.active_players [];Pyint the_state.reward;
   Pyint the_state.total_turns;dice_results;Pystr the_state.player_turn.player_id;
   notification]
(*Update board for attacks*)
let update_board_attack the_state clicked1 clicked2 notification =
  match clicked1,clicked2 with
  | Pytuple [Pystr str1; Pybool b1], Pytuple [Pystr str2; Pybool b2] ->
    call graphics "updateAttack"
      [board;clicked1;get_country_tuple the_state.occupied_countries str1;
       get_country_tuple the_state.occupied_countries str2;
    card_amounts_python the_state.active_players [];Pyint the_state.reward;
     Pyint the_state.total_turns;dice_results;Pystr the_state.player_turn.player_id;
    notification];
  | _ -> failwith "Should not be here"

let update_notification (notification) = call graphics "updateNotificationBar" [notification]

(* Get time of computer system*)
let time = int_of_float (Sys.time ())

let startgame_reinforce_notification st =
  Pystr (st.player_turn.player_id ^ ": Please place a troop on an unoccupied country")

let startgame_populate_notification st =
  Pystr (st.player_turn.player_id ^ ": Please place a troop on one of your countries")

let reinforce_notification st =
  Pystr (st.player_turn.player_id ^ ": Reinforce " ^ (string_of_int st.player_turn.num_undeployed) ^ " troops")

let attack_notification_from st =
  Pystr (st.player_turn.player_id ^ ": Select a country you own to attack from, or pass to fortification")

let attack_notification_to st =
  Pystr (st.player_turn.player_id ^ ": Now, select an opponent's country to battle!")

let earn_card_notification st =
  Pystr (st.player_turn.player_id ^ ": You earned a cash card for conquering a country on your turn!")

let fortification_notification st =
  Pystr (st.player_turn.player_id ^ ": Select one of your countries to pull out troops from, or pass to end your turn")

let eliminated_notification st =
  Pystr (st.player_turn.player_id ^ ": You eliminated a player from the game!")

let next_turn_notification st =
  Pystr (st.player_turn.player_id ^ ": It's your turn!")

let cash_in_notification st =
  Pystr (st.player_turn.player_id ^ ": Cashing in cards if available...")


let is_ai st =
  if (st.player_turn.ai) then true else false

(* Creates a reinforcement loop that performs the reinforcement action*)
let rec reinforce_type st reinforce_cmd_type rein_type =

  let undeploys = st.player_turn.num_undeployed in
  if (undeploys = 0) then st
  else
  if (is_ai st) then
    let next_string = ai_next_reinforce st in
    let cmd = reinforce_cmd_type (next_string) st in
    let st' = rein_type cmd st in (update_board_with_click st' (Pytuple [Pystr next_string; Pybool true])
       (if undeploys > 1 then reinforce_notification st'
        (* else if ((undeploys = 1))
        then reinforce_notification st' *)
        else attack_notification_from st'));
    reinforce_type st' reinforce_cmd_type rein_type
  else (
    let clicked = get graphics "clicker" [board] in
    update_notification (reinforce_notification st);
    if (bool_of_clicked clicked) then
      (let cmd = reinforce_cmd_type (string_of_clicked clicked) st in
       let st' = rein_type cmd st in (update_board_with_click st' clicked
        (if undeploys > 1 then reinforce_notification st'
         else if ((undeploys = 1) && (bool_of_clicked clicked = false)) || ((undeploys = 1) && (owns_country (string_of_clicked clicked) st.occupied_countries st.player_turn <> true))
         then reinforce_notification st'
         else attack_notification_from st'));
       reinforce_type st' reinforce_cmd_type rein_type) else reinforce_type st reinforce_cmd_type rein_type)

let rec reinforce_until_occupied_loop st =
  if (List.length st.occupied_countries = 24) then (update_board_no_click st (startgame_populate_notification st); st)
  else
  if (is_ai st) then
    let next_string = ai_next_initial_reinforce st in
    let cmd = init_reinforce_command (next_string) st in
    let st' = reinforce_begin cmd st in (update_board_with_click st' (Pytuple [Pystr next_string; Pybool true]) (startgame_reinforce_notification st'));
    reinforce_until_occupied_loop st'
  else (
   let clicked = get graphics "clicker" [board] in
   if (bool_of_clicked clicked) then
     let cmd = init_reinforce_command (string_of_clicked clicked) st in
     match cmd with
     | FalseReinforce -> reinforce_until_occupied_loop st
     | Reinforce _ ->
       (let st' = reinforce_begin cmd st in update_board_with_click st' clicked (startgame_reinforce_notification st');
        reinforce_until_occupied_loop st')
   else reinforce_until_occupied_loop st)

let rec reinforce_occupied_loop st =
  if (all_troops_deployed st.active_players) then st
  else
    (if (is_ai st) then
       let next_string = ai_next_reinforce st in
       let cmd = make_reinforce_command (next_string) st in
       let st' = next_player (reinforce cmd st) in update_board_with_click st' (Pytuple [Pystr next_string; Pybool true]) (startgame_populate_notification st');
       reinforce_occupied_loop st'
     else (
       let clicked = get graphics "clicker" [board] in
       if (bool_of_clicked clicked) then
         let cmd = make_reinforce_command (string_of_clicked clicked) st in
         match cmd with
         | FalseReinforce -> reinforce_occupied_loop st
         | Reinforce _ ->
           (let st' = next_player (reinforce cmd st) in update_board_with_click st' clicked (startgame_populate_notification st');
            reinforce_occupied_loop st')
       else reinforce_occupied_loop st))

(* Creates a reinforcement loop for the middle of the game *)
let midgame_reinforce_loop st = reinforce_type st make_reinforce_command reinforce

let rec reinforce_till_occupied_attack st option1 option2 =
  let undeploys = st.player_turn.num_undeployed in
  if st.player_turn.num_undeployed = 0 then st else
    (if is_ai st then
       let next_string = ai_next_reinforce_after_attack st option1 option2 in
       let cmd = make_reinforce_command next_string st in
       let st2 = reinforce cmd st in
       (update_board_with_click st2 (Pytuple [Pystr next_string; Pybool true])
          (if undeploys >= 1 then reinforce_notification st2
           else attack_notification_from st2));
       reinforce_till_occupied_attack st2 option1 option2
     else
       let clicked = get graphics "clicker" [board] in
       update_notification (reinforce_notification st);
       if bool_of_clicked clicked = false then reinforce_till_occupied_attack st option1 option2 else
         let clickedstring = string_of_clicked clicked in
         if clickedstring = option1 || clickedstring = option2 then
           let cmd = make_reinforce_command clickedstring st in
           let st2 = reinforce cmd st in
           (update_board_with_click st2 clicked
              (if undeploys > 1 then reinforce_notification st2
               else if ((undeploys = 1) && (bool_of_clicked clicked = false)) || ((undeploys = 1) && (owns_country (string_of_clicked clicked) st.occupied_countries st.player_turn <> true))
               then reinforce_notification st2
               else attack_notification_from st2));
           reinforce_till_occupied_attack st2 option1 option2
         else reinforce_till_occupied_attack st option1 option2)
(* Creates a reinforcement loop for the start of the game when players
   begin claiming countries*)
(* let startgame_reinforce_loop st = reinforce_type st init_reinforce_command reinforce_begin *)

let trade_in st =
  let cmd = make_trade_command st in
  trade_in cmd st

let rec fortify_loop st =
  update_notification (fortification_notification st);
  if(is_ai st) then
    let next_string = ai_next_fortify st in
    if next_string = "none" then
      let cmd = make_fortify_command "End turn" st in
      fortify cmd st
    else
      let cmd = make_fortify_command next_string st in
      let st' = fortify cmd st in
      update_board_with_click st' (Pytuple [Pystr next_string; Pybool true]) (reinforce_notification st'); midgame_reinforce_loop st'
  else
    let clicked = get graphics "clicker" [board] in
    if (string_of_clicked clicked = "End turn") then st else
      let cmd = make_fortify_command (string_of_clicked clicked) st in
      let st' = fortify cmd st in
      if (st = st') then fortify_loop st
      else (update_board_with_click st' clicked (reinforce_notification st');midgame_reinforce_loop st')

let roll num_dice = if (num_dice = 1) then [(Random.int 6)+1]
  else if (num_dice = 2) then [((Random.int 6)+1); (Random.int 6)+1]
  else [(Random.int 6)+1; (Random.int 6)+1; (Random.int 6)+1]

let find_max lst = (List.sort compare lst) |> List.rev |> List.hd

let find_2nd_max lst =
  match List.rev (List.sort compare lst) with
  | h1::h2::t -> h2
  | _ -> -1

let rec get_click_two st clicked1 clicked1string =
  let clicked2 = get graphics "clicker" [board] in
  let clicked2string = (string_of_clicked clicked2) in
  if (owns_country clicked2string st.occupied_countries st.player_turn = true && get_num_troops clicked2string st.occupied_countries > 1)
  then get_click_two st clicked2 clicked2string
  else if owns_country clicked2string st.occupied_countries st.player_turn = true
  then (update_board_with_click st clicked1 (attack_notification_from st); ((Pystr "false",""),(Pystr "","")))
  else ((clicked2, clicked2string),(clicked1,clicked1string))


(* Creates an attack loop that can be existed if user hits end turn*)
let rec attack_loop st =   (*have to check if one side lost*)
  Random.init (int_of_float (Unix.time ()));
  if is_ai st then
    let next_tuple = ai_next_attack st in
    let next_attack = fst next_tuple in
    let next_defender = snd next_tuple in
    if next_tuple = ("none", "none") then st else
      let num_attackers = get_num_troops next_attack st.occupied_countries in
      update_board_with_click st (Pytuple [Pystr next_attack; Pybool true]) (attack_notification_to st);
      Unix.sleep 1;
      update_board_with_click st (Pytuple [Pystr next_defender; Pybool true]) (attack_notification_to st);
      Unix.sleep 1;
      let num_defenders = get_num_troops next_defender st.occupied_countries in
      let attack_dice = min (num_attackers-1) 3 in
      let defend_dice = min (num_defenders) 2 in
      let rolls = (roll attack_dice, roll defend_dice) in
      (* print_list (fst rolls); print_list (snd rolls); *)
      let attack_max = find_max (fst rolls) in
      let attack_2nd_max = find_2nd_max (fst rolls) in
      let defend_max = find_max (snd rolls) in
      let defend_2nd_max = find_2nd_max (snd rolls) in
      let loser_lost = if (attack_dice > 1 && defend_dice > 1) then
          (if (attack_max > defend_max && attack_2nd_max > defend_2nd_max) then (Right, -2)
          else if (attack_max <= defend_max && attack_2nd_max <=  defend_2nd_max) then (Left, -2)
          else (Both, -1))
        else (if (attack_max > defend_max) then (Right, -1) else (Left, -1)) in
      let cmd = make_attack_command next_attack next_defender
          (fst loser_lost) (snd loser_lost) st in
      let st2 = attack cmd st in
      (if (num_countries st2.player_turn st2.occupied_countries 0 > num_countries st.player_turn st.occupied_countries 0
           && st2.player_turn.num_undeployed > 0) then
         update_board_attack st2 (Pytuple [Pystr next_attack; Pybool true]) (Pytuple [Pystr next_defender; Pybool true]) (reinforce_notification st2) else
         update_board_attack st2 (Pytuple [Pystr next_attack; Pybool true]) (Pytuple [Pystr next_defender; Pybool true]) (attack_notification_from st2));
      if num_countries st2.player_turn st2.occupied_countries 0 = 24 then st2
      else if num_countries st2.player_turn st2.occupied_countries 0 > num_countries st.player_turn st.occupied_countries 0 then
        let st3 = reinforce_till_occupied_attack st2 next_attack next_defender in
        attack_loop st3
      else attack_loop st2
  else
    let clicked1 = get graphics "clicker" [board] in
    let clicked1string = (string_of_clicked clicked1) in
    if (clicked1string = "End turn") then (update_board_with_click st clicked1 (Pystr ""); st)
    else if (owns_country clicked1string st.occupied_countries st.player_turn <> true)
    then ((update_board_with_click st clicked1 (attack_notification_from st)); attack_loop st)
    else if get_num_troops clicked1string st.occupied_countries = 1
    then ((update_board_with_click st clicked1 (attack_notification_from st)); attack_loop st)
    else
      (update_board_with_click st clicked1 (attack_notification_to st);
       let clicked2stringtuple = get_click_two st clicked1 clicked1string in
       if clicked2stringtuple = ((Pystr "false",""),(Pystr "","")) then attack_loop st
       else
         let clicked2 = fst (fst clicked2stringtuple) in
         let clicked2string = snd (fst clicked2stringtuple) in
         let clicked1 = fst (snd clicked2stringtuple) in
         let clicked1string = snd (snd clicked2stringtuple) in
         if (clicked2string = "End turn") then st else
           let num_attackers = get_num_troops clicked1string st.occupied_countries in
           let num_defenders = get_num_troops clicked2string st.occupied_countries in
           if (num_attackers < 2) then attack_loop st
           else
             (let attack_dice = min (num_attackers-1) 3 in
              let defend_dice = min (num_defenders) 2 in
              let rolls = (roll attack_dice, roll defend_dice) in
              (* print_list (fst rolls); print_list (snd rolls); *)
              let attack_max = find_max (fst rolls) in
              let attack_2nd_max = find_2nd_max (fst rolls) in
              let defend_max = find_max (snd rolls) in
              let defend_2nd_max = find_2nd_max (snd rolls) in
              let loser_lost = if (attack_dice > 1 && defend_dice > 1) then
                  (if (attack_max > defend_max && attack_2nd_max > defend_2nd_max) then (Right, -2)
                   else if (attack_max <= defend_max && attack_2nd_max <=  defend_2nd_max) then (Left, -2)
                   else (Both, -1))
                else (if (attack_max > defend_max) then (Right, -1) else (Left, -1)) in
              let cmd = make_attack_command (string_of_clicked clicked1) (string_of_clicked clicked2)
                  (fst loser_lost) (snd loser_lost) st in
              let st2 = attack cmd st in
              (if (num_countries st2.player_turn st2.occupied_countries 0 > num_countries st.player_turn st.occupied_countries 0
                   && st2.player_turn.num_undeployed > 0) then
                 update_board_attack st2 clicked1 clicked2 (reinforce_notification st2) else
                 update_board_attack st2 clicked1 clicked2 (attack_notification_from st2));
              if num_countries st2.player_turn st2.occupied_countries 0 = 24 then st2
              else if num_countries st2.player_turn st2.occupied_countries 0 > num_countries st.player_turn st.occupied_countries 0 then
                let st3 = reinforce_till_occupied_attack st2 clicked1string clicked2string in
                attack_loop st3
              else attack_loop (st2)))

(* [repl st has_won] is the heart of the game's REPL. It performs all actions
    in the RISK Board Game systematically for every player. It is initially
    called with an initial state for [st] and a False for [has_won]
   Preconditions: [st] is a state
                  [has_won] is a boolean
*)
let rec repl st has_won =
  if (has_won) then st (*display win message*)
  else
    ((update_board_no_click st (Pystr ""));
    let st' = build_continent_list st in
    let st1 = trade_in st' in (update_board_no_click st1 (cash_in_notification st1)); Unix.sleep 2;
    let st1' = give_troops st1 in
    update_notification (reinforce_notification st1');
    let st2 = midgame_reinforce_loop (st1') in
    let st3 = attack_loop st2 in (update_board_no_click st3) (Pystr "");
    if num_countries st3.player_turn st3.occupied_countries 0 = 24 then repl st3 true else
    let st4 = give_card st2 st3 in
    (if st3 = st4 then update_board_no_click st4 (Pystr "") else (update_board_no_click st4 (earn_card_notification st4); Unix.sleep 2));
      (* (update_board_no_click st4) (if st3 = st4 then Pystr "" else earn_card_notification st4); Unix.sleep 2; *)
    let st5 = fortify_loop st4 in (update_board_no_click st4) (Pystr "");
    (* let st6 = midgame_reinforce_loop st5 in *)
    let st6 = st5 in
    (* print_int (List.length st6.active_players); *)
    let st6' = remove_player st6 in
    (if st6 = st6' then update_board_no_click st6' (Pystr "") else (update_board_no_click st6' (eliminated_notification st6'); Unix.sleep 2));
    (* (update_board_no_click st6') (if st6 = st6' then Pystr "" else eliminated_notification st6'); Unix.sleep 2; *)
    (* print_int (List.length st6'.active_players); *)
    let st7 = next_player st6' in (update_board_no_click st7) (next_turn_notification st7); Unix.sleep 1;
    let won = check_if_win st7 in
    repl st7 won)
    (* let clicked1 = get graphics "clicker" [board] in
    st4 *)



let p1 = {
  player_id = "Player one";
  num_deployed = 0;
  num_undeployed = 10;
  cards = [];
  score = 0;
  ai = false
}

let p2 = {
  player_id = "Player two";
  num_deployed = 0;
  num_undeployed = 10;
  cards = [];
  score = 0;
  ai = false
}

let p3 = {
  player_id = "Player three";
  num_deployed = 0;
  num_undeployed = 10;
  cards = [];
  score = 0;
  ai = false
}

let p4 = {
  player_id = "Player four";
  num_deployed = 0;
  num_undeployed = 10;
  cards = [];
  score = 0;
  ai = false
}

let ai1 = {
  player_id = "Player one";
  num_deployed = 0;
  num_undeployed= 0;
  cards = [];
  score = 0;
  ai = true
}

let ai2 = {
  player_id = "Player two";
  num_deployed = 0;
  num_undeployed = 0;
  cards = [];
  score = 0;
  ai = true
}

let ai3 = {
  player_id = "Player three";
  num_deployed = 0;
  num_undeployed = 0;
  cards = [];
  score = 0;
  ai = true
}

let ai4 = {
  player_id = "Player four";
  num_deployed = 0;
  num_undeployed = 0;
  cards = [];
  score = 0;
  ai = true
}

(* let clicked = get graphics "clicker" [board] in
(match clicked with
  | Pytuple [Pystr st; Pybool b] ->
  call graphics "updateBoard"
  [board;
  clicked;
  occupied_countries_python st1.occupied_countries [];
  card_amounts_python st1.active_players [];
  Pyint st1.reward;
  Pyint st1.total_turns;
  dice_results;
  Pystr st1.player_turn.player_id];
  | _ -> failwith "Should not be here")
   ); *)

let rec get_num_AI num_players =
 let num = string_of_int num_players in
 ANSITerminal.(print_string [green] ("How many AI's would you like to play with? (0-"^num^")\n> "));
 let num_AI = try (int_of_string (read_line ()))
   with _ -> (ANSITerminal.(print_string [red] ("\nPlease enter an integer from 0 to "^num^"\n")); get_num_AI num_players) in
 if (num_AI >= 0 && num_AI <= num_players) then num_AI
 else (ANSITerminal.(print_string [red] ("\nPlease enter an integer from 0 to "^num^"\n")); get_num_AI num_players)

let rec get_num_players () =
 ANSITerminal.(print_string [green] ("How many players would you like to play with? (2-4)\n> "));
 let num_players = try (int_of_string (read_line ()))
   with _ -> ANSITerminal.(print_string [red] ("\nPlease enter an integer from 2 to 4\n")); get_num_players ()
 in if (num_players >= 2 && num_players <= 4) then num_players
 else (ANSITerminal.(print_string [red] ("\nPlease enter an integer from 2 to 4\n")); get_num_players ())

let () =

 ANSITerminal.(print_string [green] ("Welcome to Big Red Risk!\n"));
 let num_players = get_num_players () in
 let num_AI = get_num_AI num_players in
 let num_humans = num_players - num_AI in
 let num_starting =
   if (num_players = 2) then 15
   else if (num_players = 3) then 10
   else 8 in
 let ai_list =
   if (num_AI = 0) then []
   else if (num_AI = 1) then [{ai4 with num_undeployed = num_starting}]
   else if (num_AI = 2) then [{ai3 with num_undeployed = num_starting};{ai4 with num_undeployed = num_starting}]
   else if (num_AI = 3) then [{ai2 with num_undeployed = num_starting};{ai3 with num_undeployed = num_starting};{ai4 with num_undeployed = num_starting}]
   else [{ai1 with num_undeployed = num_starting};{ai2 with num_undeployed = num_starting};{ai3 with num_undeployed = num_starting};{ai4 with num_undeployed = num_starting}] in

 let human_list =
   if (num_humans = 0) then []
   else if (num_humans = 1) then [{p1 with num_undeployed = num_starting}]
   else if (num_humans = 2) then [{p1 with num_undeployed = num_starting};{p2 with num_undeployed = num_starting}]
   else if (num_humans = 3) then [{p1 with num_undeployed = num_starting};{p2 with num_undeployed = num_starting};{p3 with num_undeployed = num_starting}]
   else [{p1 with num_undeployed = num_starting};{p2 with num_undeployed = num_starting};{p3 with num_undeployed = num_starting};{p4 with num_undeployed = num_starting}] in

 let player_list =
   (* if (num_players = 2) then [{p1 with num_undeployed = 15};{p2 with num_undeployed = 15}]
   else if num_players = 3 then [{p1 with num_undeployed = 10};{p2 with num_undeployed = 10};{p3 with num_undeployed = 10}]
      else [{p1 with num_undeployed = 8};{p2 with num_undeployed = 8};{p3 with num_undeployed = 8};{p4 with num_undeployed = 8}] in *)
   human_list @ ai_list in
  let i_state = init_state num_players player_list graphboard in
  update_notification (startgame_reinforce_notification i_state);
  let st1 = reinforce_until_occupied_loop i_state in
  let st2 = reinforce_occupied_loop st1 in
  repl st2 false;


(*
  let board = get graphics "drawBoard" [] in
  let dice_results = Pytuple [Pylist[Pyint 6; Pyint 5; Pyint 3];Pylist[Pyint 6; Pyint 1;]] in

  let i_state = init_state 3 [p1;p2;p3] in

(* loop_repl i_state False *)
  let quit_loop = ref false in
  while not !quit_loop do
  print_string "Have you had enough yet? (y/n) ";

  let clicked = get graphics "clicker" [board] in
  let s = match clicked with
    | Pytuple [Pystr st; Pybool b] ->
      call graphics "updateBoard"
          [board;
           clicked;
           occupied_countries_python i_state.occupied_countries [];
           card_amounts_python i_state.active_players [];
           Pyint i_state.reward;
           Pyint i_state.total_turns;
           dice_results;
           Pystr i_state.player_turn.player_id]
    | _ -> failwith "Should not be here"
  in s;
  done;; *)

  (* let init_state player_num players = {
    num_players = player_num;
    player_turn = List.hd players;
    total_turns = 0;
    active_players = players;
    reward = 5;
    occupied_countries = [];
    occupied_continents = [];
    board = board;
  } *)
(*
  let occupied_countries = Pylist [Pytuple [Pystr "Country one";Pystr "Player one";Pyint 556];
                                   Pytuple [Pystr "Country two";Pystr "Player one";Pyint 22];
                                   Pytuple [Pystr "Country three";Pystr "Player three";Pyint 486]] in
  let card_amounts = Pylist [Pytuple [Pystr "Player one";Pyint 5];
                             Pytuple [Pystr "Player two";Pyint 2];
                             Pytuple [Pystr "Player three";Pyint 1];] in

  let cash_card_reward = Pyint 15 in
  let dice_results = Pytuple [Pylist[Pyint 6; Pyint 5; Pyint 3];Pylist[Pyint 6; Pyint 1;]] in
  let turns_taken = 3 in

  let board = get graphics "drawBoard" [Pystr "Player one"] in
  let player_ids = ["Player one";"Player two";"Player three"] in
  let current_player_turn = "Player one" in

  let quit_loop = ref false in
  while not !quit_loop do
    print_string "Have you had enough yet? (y/n) ";

    let clicked = get graphics "clicker" [board] in
    let s = match clicked with
      | Pytuple [Pystr st; Pybool b] ->
        if (st = "End turn") then call graphics "updateBoard"
          [board;clicked;occupied_countries;card_amounts;cash_card_reward;
           Pyint turns_taken; dice_results;Pystr current_player_turn]
        else call graphics "updateBoard"
            [board;clicked;occupied_countries;card_amounts;cash_card_reward;
             Pyint turns_taken; dice_results;Pystr current_player_turn]
      | _ -> failwith "Should not be here"
    in s;

  (* let str = read_line () in
  if str.[0] = 'y' then
    quit_loop := true *)
    done;; *)



  (* let msg = get_string simple "get_message" [] in
	let integer = get_int simple "get_integer" [] in
	let addition = get_int simple "sum" [Pyint 12 ; Pyint 10] in
	let strconcat = get_string simple "sum" [Pystr "first " ; Pystr "second"] in
  Printf.printf "%s\n%d\n%d\n%s\n" msg integer addition strconcat ; *)



	close py
