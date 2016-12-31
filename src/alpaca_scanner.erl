%%% -*- mode: erlang;erlang-indent-level: 4;indent-tabs-mode: nil -*-
%%% ex: ft=erlang ts=4 sw=4 et
-module(alpaca_scanner).
-export([scan/1]).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-endif.

scan(Code) ->    
    %% Scan and infer break tokens if not provided
    case alpaca_scan:string(Code) of
        {ok, Tokens, Num} -> {ok, infer_breaks(Tokens), Num};    
        Error -> Error
    end.

infer_breaks(Tokens) ->
    %% Reduce tokens from the right, inserting a break (i.e. ';;') before
    %% top level constructs including let, type, exports, imports and module.
    %% To avoid inserting breaks in let... in... we track the level of these
    %% (as we're folding right, an 'in' increases the level by one, a 'let'
    %% decreases by one if the current level > 0)
    %% We also track whether we're in a binary as 'type' has a different
    %% semantic there
    
    Reducer = fun(Token, {LetLevel, InBinary, Acc}) ->                     
        {Symbol, Line} = case Token of
            {S, L} when is_integer(L)-> {S, L};
            Other -> {other, 0}
        end,
        InferBreak = fun() -> 
            {0, InBinary, [{break, 0} | [ Token | Acc]]} 
        end,
        Pass = fun() -> 
            {LetLevel, InBinary, [Token | Acc]} 
        end,
        ChangeLetLevel = fun(Diff) -> 
            {LetLevel + Diff, InBinary, [Token | Acc]}
        end,                   
        BinOpen = fun(State) ->
            {LetLevel, State, [Token | Acc]}
        end,
        case Symbol of
            'in'           -> ChangeLetLevel(+1);                     
            'let'          -> case LetLevel of                                            
                                0 -> InferBreak();
                                _ -> ChangeLetLevel(-1)
                              end;
            'type_declare' -> case InBinary of 
                                true -> Pass();
                                false -> InferBreak()
                              end;
            'bin_open'     -> BinOpen(false);
            'bin_close'    -> BinOpen(true);
            'test'         -> InferBreak();
            'module'       -> InferBreak();
            'export'       -> InferBreak();
            'export_type'  -> InferBreak();
            'import_type'  -> InferBreak();
            _              -> Pass()
        end      
    end,
    {0, false, Output} = lists:foldr(Reducer, {0, false, []}, Tokens),
    %% Remove initial 'break' if one was inferred
    case Output of
        [{break, 0} | Rest] -> Rest;
        _ -> Output
    end. 

-ifdef(TEST).

number_test_() ->
    [
     ?_assertEqual({ok, [{int, 1, 5}], 1}, scan("5")),
     ?_assertEqual({ok, [{float, 1, 3.14}], 1}, scan("3.14")),
     ?_assertEqual({ok, [{float, 1, 102.0}], 1}, scan("102.0"))
    ].

tuple_test_() ->
    EmptyTupleExpected = {ok, [{'(', 1}, {')', 1}], 1},
    [
     ?_assertEqual({ok, [
                         {'(', 1},
                         {int, 1, 1},
                         {')', 1}], 1},
                   scan("(1)")),
     ?_assertEqual(EmptyTupleExpected, scan("()")),
     ?_assertEqual(EmptyTupleExpected, scan("( )")),
     ?_assertEqual({ok, [
                         {'(', 1},
                         {int, 1, 1},
                         {',', 1},
                         {int, 1, 2},
                         {',', 1},
                         {int, 1, 3},
                         {')', 1}], 1},
                   scan("(1, 2, 3)"))
    ].

symbol_test_() ->
    [?_assertEqual({ok, [{symbol, 1, "mySym"}], 1}, scan("mySym")),
     ?_assertEqual({ok, [{symbol, 1, "mySym1"}], 1}, scan("mySym1")),
     ?_assertEqual({ok, [{symbol, 1, "mysym"}], 1}, scan("mysym"))].

atom_test_() ->
    [?_assertEqual({ok, [{atom, 1, "myAtom"}], 1}, scan(":myAtom"))].

let_test() ->
    Code = "let symbol = 5",
    ExpectedTokens = [{'let', 1},
                      {symbol, 1, "symbol"},
                      {assign, 1},
                      {int, 1, 5}],
    ?assertEqual({ok, ExpectedTokens, 1}, scan(Code)).

-endif.
