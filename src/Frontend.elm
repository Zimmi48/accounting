module Frontend exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Date
import DatePicker
import Dialog
import Dict
import Dict.Extra as Dict
import Element exposing (..)
import Element.Background as Background
import Element.Border as Border
import Element.Input as Input
import Html
import Html.Attributes as Attr
import Html.Events exposing (..)
import Lamdera
import List.Extra as List
import Maybe.Extra as Maybe
import String
import Task
import Tuple exposing (..)
import Types exposing (..)
import Url


type alias Model =
    FrontendModel


app =
    Lamdera.frontend
        { init = init
        , onUrlRequest = UrlClicked
        , onUrlChange = UrlChanged
        , update = update
        , updateFromBackend = updateFromBackend
        , subscriptions = \m -> Sub.none
        , view = view
        }


init : Url.Url -> Nav.Key -> ( Model, Cmd FrontendMsg )
init url key =
    ( { showDialog = Nothing
      , key = key
      }
    , Cmd.none
    )


update : FrontendMsg -> Model -> ( Model, Cmd FrontendMsg )
update msg model =
    case msg of
        UrlClicked urlRequest ->
            case urlRequest of
                Internal url ->
                    ( model
                    , Nav.pushUrl model.key (Url.toString url)
                    )

                External url ->
                    ( model
                    , Nav.load url
                    )

        UrlChanged url ->
            ( model, Cmd.none )

        NoOpFrontendMsg ->
            ( model, Cmd.none )

        ShowAddPersonDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddPersonDialog
                            { name = ""
                            , nameInvalid = False
                            , submitted = False
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddAccountDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddAccountOrGroupDialog
                            { name = ""
                            , nameInvalid = False
                            , ownersOrMembers = []
                            , submitted = False
                            , account = True
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddGroupDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddAccountOrGroupDialog
                            { name = ""
                            , nameInvalid = False
                            , ownersOrMembers = []
                            , submitted = False
                            , account = False
                            }
                        )
              }
            , Cmd.none
            )

        ShowAddSpendingDialog ->
            ( { model
                | showDialog =
                    Just
                        (AddSpendingDialog
                            { description = ""
                            , date = Nothing
                            , dateText = ""
                            , datePickerModel = DatePicker.init
                            , totalSpending = ""
                            , sharedSpending = []
                            , transactions = []
                            , submitted = False
                            }
                        )
              }
            , Task.perform SetToday Date.today
            )

        SetToday today ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | datePickerModel = DatePicker.setToday today dialogModel.datePickerModel
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        Submit ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    ( { model | showDialog = Just (AddPersonDialog { dialogModel | submitted = True }) }
                    , Lamdera.sendToBackend (AddPerson dialogModel.name)
                    )

                Just (AddAccountOrGroupDialog dialogModel) ->
                    let
                        ownersOrMembers =
                            dialogModel.ownersOrMembers
                                |> List.map
                                    (\( ownerOrMember, share, _ ) ->
                                        ( ownerOrMember
                                        , share
                                            |> String.toInt
                                            |> Maybe.withDefault 0
                                        )
                                    )
                                |> Dict.fromListDedupe (+)
                                |> Dict.map (\_ -> Share)
                    in
                    ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | submitted = True }) }
                    , if dialogModel.account then
                        Lamdera.sendToBackend (AddAccount dialogModel.name ownersOrMembers)

                      else
                        Lamdera.sendToBackend (AddGroup dialogModel.name ownersOrMembers)
                    )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | submitted = True }) }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        Cancel ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

        UpdateName name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddPersonDialog { dialogModel | name = name, nameInvalid = False }) }
                        , Lamdera.sendToBackend (CheckNoPerson name)
                        )

                Just (AddAccountOrGroupDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | name = name, nameInvalid = False }) }
                        , if dialogModel.account then
                            Lamdera.sendToBackend (CheckNoAccount name)

                          else
                            Lamdera.sendToBackend (CheckNoGroup name)
                        )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | description = name }) }
                    , Cmd.none
                    )

                Nothing ->
                    ( model, Cmd.none )

        UpdateOwnerOrMember index ownerOrMember share ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            if index == 0 then
                                                ( ownerOrMember, share, Incomplete ) :: dialogModel.ownersOrMembers

                                            else if index == 1 && ownerOrMember == "" then
                                                List.drop 1 dialogModel.ownersOrMembers

                                            else
                                                List.setAt (index - 1) ( ownerOrMember, share, Incomplete ) dialogModel.ownersOrMembers
                                    }
                                )
                      }
                    , if String.length ownerOrMember > 0 then
                        Lamdera.sendToBackend (AutocompletePerson ownerOrMember)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateTotalSpending totalSpending ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | totalSpending = totalSpending }) }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ChangeDatePicker changeEvent ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    (case changeEvent of
                                        DatePicker.DateChanged date ->
                                            { dialogModel | date = Just date, dateText = Date.toIsoString date }

                                        DatePicker.TextChanged dateText ->
                                            { dialogModel
                                                | date =
                                                    Date.fromIsoString dateText
                                                        |> Result.toMaybe
                                                , dateText = dateText
                                            }

                                        DatePicker.PickerChanged subMsg ->
                                            { dialogModel | datePickerModel = DatePicker.update subMsg dialogModel.datePickerModel }
                                    )
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateGroupSpending index description amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | sharedSpending =
                                            if index == 0 then
                                                ( description, amount, Incomplete ) :: dialogModel.sharedSpending

                                            else if index == 1 && description == "" then
                                                List.drop 1 dialogModel.sharedSpending

                                            else
                                                List.setAt (index - 1) ( description, amount, Incomplete ) dialogModel.sharedSpending
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateTransaction index account amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            if index == 0 then
                                                ( account, amount, Incomplete ) :: dialogModel.transactions

                                            else if index == 1 && account == "" then
                                                List.drop 1 dialogModel.transactions

                                            else
                                                List.setAt (index - 1) ( account, amount, Incomplete ) dialogModel.transactions
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )

        OperationSuccessful ->
            ( { model | showDialog = Nothing }
            , Cmd.none
            )

        PersonAlreadyExists name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    if dialogModel.name == name then
                        ( { model | showDialog = Just (AddPersonDialog { dialogModel | nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        AccountAlreadyExists name ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    if dialogModel.name == name && dialogModel.account then
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        GroupAlreadyExists name ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    if dialogModel.name == name && not dialogModel.account then
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        InvalidPersonPrefix prefix ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> List.map
                                                    (\( ownerOrMember, share, nameValidity ) ->
                                                        if String.startsWith prefix ownerOrMember then
                                                            ( ownerOrMember, share, InvalidPrefix )

                                                        else
                                                            ( ownerOrMember, share, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UniquePersonPrefix prefix name ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> List.map
                                                    (\( ownerOrMember, share, nameValidity ) ->
                                                        if String.startsWith prefix ownerOrMember then
                                                            ( name, share, Complete )

                                                        else
                                                            ( ownerOrMember, share, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        CompleteNotUniquePerson name ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> List.map
                                                    (\( ownerOrMember, share, nameValidity ) ->
                                                        if ownerOrMember == name then
                                                            ( ownerOrMember, share, Complete )

                                                        else
                                                            ( ownerOrMember, share, nameValidity )
                                                    )
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


view : Model -> Browser.Document FrontendMsg
view model =
    let
        config title inputs canSubmit =
            { closeMessage = Just Cancel
            , maskAttributes = []
            , containerAttributes =
                [ Background.color (rgb 1 1 1)
                , Border.solid
                , Border.rounded 5
                , Border.width 1
                , centerX
                , centerY
                ]
            , headerAttributes =
                [ padding 20
                , Background.color green
                ]
            , bodyAttributes = [ padding 20 ]
            , footerAttributes =
                [ Border.widthEach { top = 1, bottom = 0, left = 0, right = 0 }
                , Border.solid
                ]
            , header = Just (text title)
            , body =
                Just
                    (column [ spacing 20 ]
                        inputs
                    )
            , footer =
                Just
                    (row [ centerX, spacing 20, padding 20, alignRight ]
                        [ Input.button redButtonStyle
                            { label = text "Cancel"
                            , onPress = Just Cancel
                            }
                        , Input.button
                            (if canSubmit then
                                greenButtonStyle

                             else
                                grayButtonStyle
                            )
                            { label = text "Submit"
                            , onPress =
                                if canSubmit then
                                    Just Submit

                                else
                                    Nothing
                            }
                        ]
                    )
            }

        dialogConfig =
            model.showDialog
                |> Maybe.map
                    (\dialog ->
                        case dialog of
                            AddPersonDialog dialogModel ->
                                config "Add Person"
                                    (nameInput dialogModel)
                                    (String.length dialogModel.name
                                        > 0
                                        && not dialogModel.submitted
                                        && not dialogModel.nameInvalid
                                    )

                            AddAccountOrGroupDialog dialogModel ->
                                let
                                    label =
                                        if dialogModel.account then
                                            "Add Account"

                                        else
                                            "Add Group"
                                in
                                config label
                                    (addAccountOrGroupInputs dialogModel)
                                    (String.length dialogModel.name
                                        > 0
                                        && (dialogModel.ownersOrMembers
                                                |> List.map
                                                    (\( _, share, nameValidity ) ->
                                                        case nameValidity of
                                                            Complete ->
                                                                String.toInt share

                                                            _ ->
                                                                Nothing
                                                    )
                                                |> Maybe.combine
                                                |> Maybe.map (List.sum >> (\sum -> sum > 0))
                                                |> Maybe.withDefault False
                                           )
                                        && not dialogModel.submitted
                                        && not dialogModel.nameInvalid
                                    )

                            AddSpendingDialog dialogModel ->
                                config "Add Spending" (addSpendingInputs dialogModel) False
                    )
    in
    { title = "Accounting"
    , body =
        -- Elm UI body
        [ layout
            [ inFront (Dialog.view dialogConfig)
            ]
            (column [ width fill ]
                [ row [ centerX, spacing 70, padding 20 ]
                    [ Input.button greenButtonStyle
                        { label = text "Add Person"
                        , onPress = Just ShowAddPersonDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Account"
                        , onPress =
                            Just ShowAddAccountDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Group"
                        , onPress =
                            Just ShowAddGroupDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Spending"
                        , onPress =
                            Just ShowAddSpendingDialog
                        }
                    ]
                ]
            )
        ]
    }


buttonStyle =
    [ spaceEvenly
    , padding 10
    , Border.solid
    , Border.rounded 5
    , Border.width 1
    ]


greenButtonStyle =
    buttonStyle ++ [ Background.color green ]


green =
    rgb255 152 251 152


redButtonStyle =
    buttonStyle ++ [ Background.color red ]


red =
    rgb 1 0.5 0.5


grayButtonStyle =
    buttonStyle ++ [ Background.color (rgb 0.8 0.8 0.8) ]


nameInput { name, nameInvalid } =
    let
        attributes =
            if nameInvalid then
                [ Background.color red ]

            else
                []
    in
    [ Input.text attributes
        { label = Input.labelLeft [] (text "Name")
        , placeholder = Nothing
        , onChange = UpdateName
        , text = name
        }
    ]


addAccountOrGroupInputs ({ ownersOrMembers, account } as model) =
    let
        label =
            if account then
                "Owner"

            else
                "Member"

        nbOwnersOrMembers =
            List.length ownersOrMembers
    in
    nameInput model
        ++ listInputs label "Share" UpdateOwnerOrMember "1" ownersOrMembers


addSpendingInputs { description, date, dateText, datePickerModel, totalSpending, sharedSpending, transactions } =
    let
        remainingSpendingAmount =
            (totalSpending |> String.toInt |> Maybe.withDefault 0)
                - (sharedSpending
                    |> List.filterMap (\( _, amount, _ ) -> amount |> String.toInt)
                    |> List.sum
                  )
                |> String.fromInt

        remainingTransactionAmount =
            (totalSpending |> String.toInt |> Maybe.withDefault 0)
                - (transactions
                    |> List.filterMap (\( _, amount, _ ) -> amount |> String.toInt)
                    |> List.sum
                  )
                |> String.fromInt
    in
    [ Input.text []
        { label = Input.labelLeft [] (text "Description")
        , placeholder = Nothing
        , onChange = UpdateName
        , text = description
        }
    , DatePicker.input []
        { label = Input.labelLeft [] (text "Date")
        , placeholder = Nothing
        , onChange = ChangeDatePicker
        , selected = date
        , text = dateText
        , settings = DatePicker.defaultSettings
        , model = datePickerModel
        }
    , Input.text []
        { label = Input.labelLeft [] (text "Total Spending")
        , placeholder = Nothing
        , onChange = UpdateTotalSpending
        , text = totalSpending
        }
    , column [ spacing 20, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
        ([ text "Group Spendings" ]
            ++ listInputs "Description" "Amount" UpdateGroupSpending remainingSpendingAmount sharedSpending
        )
    , column [ spacing 20, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
        ([ text "Transactions" ]
            ++ listInputs "Account" "Amount" UpdateTransaction remainingTransactionAmount transactions
        )
    ]


listInputs nameLabel valueLabel msg defaultValue items =
    let
        listSize =
            List.length items
    in
    (if List.all (\( name, _, _ ) -> String.length name > 0) items then
        [ row [ spacing 20 ]
            [ Input.text []
                { label =
                    Input.labelLeft []
                        (nameLabel
                            ++ " "
                            ++ (listSize + 1 |> String.fromInt)
                            |> text
                        )
                , placeholder = Nothing
                , onChange = flip (msg 0) defaultValue
                , text = ""
                }
            , Input.text []
                { label = Input.labelLeft [] (text valueLabel)
                , placeholder = Nothing
                , onChange = msg 0 ""
                , text = ""
                }
            ]
        ]

     else
        []
    )
        ++ List.indexedMap
            (\index ( name, value, nameValidity ) ->
                let
                    attributes =
                        case nameValidity of
                            InvalidPrefix ->
                                [ Background.color red ]

                            _ ->
                                []
                in
                row [ spacing 20 ]
                    [ Input.text attributes
                        { label =
                            Input.labelLeft []
                                (nameLabel
                                    ++ " "
                                    ++ (listSize - index |> String.fromInt)
                                    |> text
                                )
                        , placeholder = Nothing
                        , onChange = flip (msg (index + 1)) value
                        , text = name
                        }
                    , Input.text []
                        { label = Input.labelLeft [] (text valueLabel)
                        , placeholder = Nothing
                        , onChange = msg (index + 1) name
                        , text = value
                        }
                    ]
            )
            items
        |> List.reverse
