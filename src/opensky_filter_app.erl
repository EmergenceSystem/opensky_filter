-module(opensky_filter_app).
-export([handle/2, base_capabilities/0]).
-define(URL, "https://opensky-network.org/api/states/all").
-define(TTL, 30).

base_capabilities() ->
    em_filter:base_capabilities() ++
    [<<"flight">>, <<"flights">>, <<"aircraft">>, <<"airplane">>, <<"airplanes">>,
     <<"plane">>, <<"planes">>, <<"aviation">>, <<"callsign">>, <<"opensky">>,
     <<"live">>, <<"tracking">>, <<"flightradar">>, <<"avion">>, <<"vol">>, <<"radar">>].

handle(Body, Memory) when is_binary(Body) ->
    Q = extract_value(Body),
    Mem0 = case Memory of M when is_map(M) -> M; _ -> #{} end,
    Now = erlang:system_time(second),
    case maps:get(cache, Mem0, undefined) of
        {Ts, Res} when (Now - Ts) =< ?TTL -> {filter(Q, Res), Mem0};
        _ -> All = fetch_all(), {filter(Q, All), Mem0#{cache => {Now, All}}}
    end;
handle(_Body, Memory) -> {[], Memory}.

fetch_all() ->
    case fetch_json(?URL) of
        {ok, #{<<"states">> := States}} when is_list(States) -> States;
        _ -> []
    end.

filter("", _) -> [];
filter(Q, States) ->
    QU = string:uppercase(unicode:characters_to_binary(Q)),
    Matches = [S || S <- States, is_list(S), matches(S, QU)],
    [emb(S) || S <- lists:sublist(Matches, 25)].

matches(S, QU) ->
    case nth(S, 2) of
        CS when is_binary(CS) ->
            string:find(string:uppercase(string:trim(CS)), QU) =/= nomatch;
        _ -> false
    end.

emb(S) ->
    Icao    = safe(nth(S, 1)),
    Cs      = string:trim(safe(nth(S, 2))),
    Country = safe(nth(S, 3)),
    Lon = nth(S, 6), Lat = nth(S, 7), Alt = nth(S, 8), Vel = nth(S, 10),
    Title = txt([Cs, " (live flight)"]),
    Resume = txt([Country, " - alt ", fmt(Alt), " m - ", fmt(Vel),
                  " m/s - pos ", fmt(Lat), ", ", fmt(Lon)]),
    Url = txt(["https://globe.adsbexchange.com/?icao=", Icao]),
    #{<<"properties">> => #{<<"url">> => Url, <<"title">> => Title,
                            <<"resume">> => Resume, <<"source">> => <<"opensky">>}}.

%%==================== helpers ====================
extract_value(Body) ->
    try json:decode(Body) of
        Map when is_map(Map) ->
            binary_to_list(maps:get(<<"value">>, Map,
                           maps:get(<<"query">>, Map, <<"">>)));
        _ -> binary_to_list(Body)
    catch _:_ -> binary_to_list(Body) end.

fetch_json(Url) ->
    _ = application:ensure_all_started(inets),
    Headers = [{"User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0"}],
    case httpc:request(get, {Url, Headers},
                       [{timeout, 15000}, {ssl, [{verify, verify_none}]}],
                       [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, B}} ->
            case catch json:decode(B) of
                M when is_map(M) -> {ok, M};
                _ -> error
            end;
        _ -> error
    end.

txt(IoList) ->
    case unicode:characters_to_binary(IoList) of
        Bin when is_binary(Bin) -> Bin;
        _ -> <<>>
    end.

safe(B) when is_binary(B) -> B;
safe(L) when is_list(L) -> case unicode:characters_to_binary(L) of X when is_binary(X) -> X; _ -> <<>> end;
safe(_) -> <<>>.

fmt(N) when is_integer(N) -> integer_to_binary(N);
fmt(N) when is_float(N) -> float_to_binary(N, [{decimals, 1}]);
fmt(_) -> <<"?">>.

nth(L, I) when is_list(L), length(L) >= I -> lists:nth(I, L);
nth(_, _) -> undefined.
