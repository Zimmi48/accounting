module Evergreen.Migrate.V4 exposing (..)

{-| This migration file was automatically generated by the lamdera compiler.

It includes:

  - A migration for each of the 6 Lamdera core types that has changed
  - A function named `migrate_ModuleName_TypeName` for each changed/custom type

Expect to see:

  - `Unimplementеd` values as placeholders wherever I was unable to figure out a clear migration path for you
  - `@NOTICE` comments for things you should know about, i.e. new custom type constructors that won't get any
    value mappings from the old type by default

You can edit this file however you wish! It won't be generated again.

See <https://dashboard.lamdera.app/docs/evergreen> for more info.

-}

import Basics.Extra exposing (flip)
import Dict
import Evergreen.V1.Types
import Evergreen.V4.Types
import Lamdera.Migrations exposing (..)
import Set


frontendModel : Evergreen.V1.Types.FrontendModel -> ModelMigration Evergreen.V4.Types.FrontendModel Evergreen.V4.Types.FrontendMsg
frontendModel old =
    ModelUnchanged


backendModel : Evergreen.V1.Types.BackendModel -> ModelMigration Evergreen.V4.Types.BackendModel Evergreen.V4.Types.BackendMsg
backendModel old =
    ModelMigrated ( migrate_Types_BackendModel old, Cmd.none )


frontendMsg : Evergreen.V1.Types.FrontendMsg -> MsgMigration Evergreen.V4.Types.FrontendMsg Evergreen.V4.Types.FrontendMsg
frontendMsg old =
    MsgUnchanged


toBackend : Evergreen.V1.Types.ToBackend -> MsgMigration Evergreen.V4.Types.ToBackend Evergreen.V4.Types.BackendMsg
toBackend old =
    MsgUnchanged


backendMsg : Evergreen.V1.Types.BackendMsg -> MsgMigration Evergreen.V4.Types.BackendMsg Evergreen.V4.Types.BackendMsg
backendMsg old =
    MsgUnchanged


toFrontend : Evergreen.V1.Types.ToFrontend -> MsgMigration Evergreen.V4.Types.ToFrontend Evergreen.V4.Types.FrontendMsg
toFrontend old =
    MsgUnchanged


migrate_Types_BackendModel : Evergreen.V1.Types.BackendModel -> Evergreen.V4.Types.BackendModel
migrate_Types_BackendModel old =
    { years = old.years |> Dict.map (\k -> migrate_Types_Year old)
    , groups = old.groups |> Dict.map (\k -> migrate_Types_Group)
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\k -> Dict.map (\_ -> migrate_Types_Amount migrate_Types_Credit))
    , persons = old.persons
    , nextPersonId = old.nextPersonId
    }


migrate_Types_Amount : (a_old -> a_new) -> Evergreen.V1.Types.Amount a_old -> Evergreen.V4.Types.Amount a_new
migrate_Types_Amount migrate_a old =
    case old of
        Evergreen.V1.Types.Amount p0 ->
            Evergreen.V4.Types.Amount p0


migrate_Types_Credit : Evergreen.V1.Types.Credit -> Evergreen.V4.Types.Credit
migrate_Types_Credit old =
    case old of
        Evergreen.V1.Types.Credit ->
            Evergreen.V4.Types.Credit


migrate_Types_Group : Evergreen.V1.Types.Group -> Evergreen.V4.Types.Group
migrate_Types_Group old =
    old |> Dict.map (\k -> migrate_Types_Share)


migrate_Types_Month : Evergreen.V1.Types.BackendModel -> Evergreen.V1.Types.Month -> Evergreen.V4.Types.Month
migrate_Types_Month oldModel old =
    { days = old.spendings |> List.foldl (\spending days -> Dict.update spending.day (addSpendingToDay oldModel spending) days) Dict.empty
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\k -> Dict.map (\_ -> migrate_Types_Amount migrate_Types_Credit))
    }


addSpendingToDay : Evergreen.V1.Types.BackendModel -> Evergreen.V1.Types.Spending -> Maybe Evergreen.V4.Types.Day -> Maybe Evergreen.V4.Types.Day
addSpendingToDay oldModel spending maybeDay =
    let
        groupMembers =
            Dict.keys spending.groupCredits
                |> List.map
                    (\group ->
                        Dict.get group oldModel.groups
                            |> Maybe.map Dict.keys
                            |> Maybe.withDefault [ group ]
                    )
                |> List.concat
                |> Set.fromList

        groupMembersKey =
            Set.toList groupMembers
                |> List.filterMap (flip Dict.get oldModel.persons)
                |> List.map (.id >> String.fromInt)
                |> String.join ","

        spendingV4 =
            { description = spending.description
            , total = migrate_Types_Amount migrate_Types_Credit spending.total
            , groupCredits = spending.groupCredits |> Dict.map (\_ -> migrate_Types_Amount migrate_Types_Credit)
            }
    in
    Just (addSpendingToDay_backend groupMembersKey spendingV4 maybeDay)


migrate_Types_Share : Evergreen.V1.Types.Share -> Evergreen.V4.Types.Share
migrate_Types_Share old =
    case old of
        Evergreen.V1.Types.Share p0 ->
            Evergreen.V4.Types.Share p0


migrate_Types_Year : Evergreen.V1.Types.BackendModel -> Evergreen.V1.Types.Year -> Evergreen.V4.Types.Year
migrate_Types_Year oldModel old =
    { months = old.months |> Dict.map (\k -> migrate_Types_Month oldModel)
    , totalGroupCredits = old.totalGroupCredits |> Dict.map (\k -> Dict.map (\_ -> migrate_Types_Amount migrate_Types_Credit))
    }


addSpendingToDay_backend groupMembersKey spending maybeDay =
    case maybeDay of
        Nothing ->
            { spendings = [ spending ]
            , totalGroupCredits =
                Dict.singleton groupMembersKey spending.groupCredits
            }

        Just day ->
            { spendings = spending :: day.spendings
            , totalGroupCredits =
                day.totalGroupCredits
                    |> addToTotalGroupCredits groupMembersKey spending
            }


addToTotalGroupCredits groupMembersKey { groupCredits } =
    Dict.update groupMembersKey
        (Maybe.map (addAmounts groupCredits >> Just)
            >> Maybe.withDefault (Just groupCredits)
        )


addAmount value maybeAmount =
    case maybeAmount of
        Nothing ->
            Just (Evergreen.V4.Types.Amount value)

        Just (Evergreen.V4.Types.Amount amount) ->
            Just (Evergreen.V4.Types.Amount (amount + value))


addAmounts =
    Dict.foldl
        (\key (Evergreen.V4.Types.Amount value) ->
            Dict.update key (addAmount value)
        )
