module Frontend exposing (..)

import Basics.Extra exposing (flip)
import Browser exposing (UrlRequest(..))
import Browser.Navigation as Nav
import Date
import DatePicker
import Dialog
import Dict exposing (Dict)
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
import Regex
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
      , user = ""
      , nameValidity = Incomplete
      , userGroupsAndAccounts = Nothing
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
                            , groupSpendings = []
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
                    let
                        groupSpendings =
                            dialogModel.groupSpendings
                                |> List.map
                                    (\( group, amount, _ ) ->
                                        ( group
                                        , amount
                                            |> parseAmountValue
                                            |> Maybe.withDefault 0
                                        )
                                    )
                                |> Dict.fromListDedupe (+)
                                |> Dict.map (\_ -> Amount)

                        transactions =
                            dialogModel.transactions
                                |> List.map
                                    (\( account, amount, _ ) ->
                                        ( account
                                        , amount
                                            |> parseAmountValue
                                            |> Maybe.withDefault 0
                                        )
                                    )
                                |> Dict.fromListDedupe (+)
                                |> Dict.map (\_ -> Amount)
                    in
                    case
                        ( dialogModel.date
                        , parseAmountValue dialogModel.totalSpending
                        )
                    of
                        ( Just date, Just totalSpending ) ->
                            ( { model
                                | showDialog =
                                    Just
                                        (AddSpendingDialog
                                            { dialogModel | submitted = True }
                                        )
                              }
                            , Lamdera.sendToBackend
                                (AddSpending
                                    { description = dialogModel.description
                                    , year = Date.year date
                                    , month = Date.monthNumber date
                                    , day = Date.day date
                                    , totalSpending = Amount totalSpending
                                    , groupSpendings = groupSpendings
                                    , transactions = transactions
                                    }
                                )
                            )

                        _ ->
                            ( model, Cmd.none )

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
                        , Lamdera.sendToBackend (CheckValidName name)
                        )

                Just (AddAccountOrGroupDialog dialogModel) ->
                    if name == "" then
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | name = "", nameInvalid = True }) }
                        , Cmd.none
                        )

                    else
                        ( { model | showDialog = Just (AddAccountOrGroupDialog { dialogModel | name = name, nameInvalid = False }) }
                        , Lamdera.sendToBackend (CheckValidName name)
                        )

                Just (AddSpendingDialog dialogModel) ->
                    ( { model | showDialog = Just (AddSpendingDialog { dialogModel | description = name }) }
                    , Cmd.none
                    )

                Nothing ->
                    ( { model
                        | user = name
                        , nameValidity = Incomplete
                        , userGroupsAndAccounts = Nothing
                      }
                    , Lamdera.sendToBackend (AutocompletePerson name)
                    )

        AddOwnerOrMemberName ownerOrMember ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> addNameInList ownerOrMember "1"
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompletePerson ownerOrMember)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateOwnerOrMemberName index ownerOrMember ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> updateNameInList
                                                    index
                                                    ownerOrMember
                                                    (\_ -> "1")
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

        UpdateOwnerOrMemberShare index share ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> updateValueInList index share
                                    }
                                )
                      }
                    , Cmd.none
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

        AddGroupName group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> addAccountOrGroup dialogModel group
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompleteGroup group)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateGroupName index group ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> updateNameInList
                                                    index
                                                    group
                                                    (computeRemainder dialogModel)
                                    }
                                )
                      }
                    , if String.length group > 0 then
                        Lamdera.sendToBackend (AutocompleteGroup group)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateGroupAmount index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> updateValueInList index amount
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AddAccountName account ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> addAccountOrGroup dialogModel account
                                    }
                                )
                      }
                    , Lamdera.sendToBackend (AutocompleteAccount account)
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateAccountName index account ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> updateNameInList
                                                    index
                                                    account
                                                    (computeRemainder dialogModel)
                                    }
                                )
                      }
                    , if String.length account > 0 then
                        Lamdera.sendToBackend (AutocompleteAccount account)

                      else
                        Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        UpdateAccountAmount index amount ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> updateValueInList index amount
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )


computeRemainder { totalSpending } list =
    ((totalSpending
        |> parseAmountValue
        |> Maybe.withDefault 0
     )
        - (list
            |> List.filterMap (\( _, amount, _ ) -> amount |> parseAmountValue)
            |> List.sum
          )
    )
        |> viewAmount


addAccountOrGroup model name list =
    addNameInList name (computeRemainder model list) list


addNameInList name defaultValue list =
    ( name, defaultValue, Incomplete ) :: list


updateNameInList index name computeDefaultValue list =
    if index == 0 && name == "" then
        case list of
            [] ->
                []

            ( _, value, _ ) :: tail ->
                if value == "" || value == computeDefaultValue tail then
                    tail

                else
                    ( name, value, Incomplete ) :: tail

    else
        list
            |> List.updateAt index
                (\( _, value, _ ) ->
                    ( name, value, Incomplete )
                )


updateValueInList index value list =
    if index == 0 && value == "" then
        case list of
            [] ->
                []

            ( name, _, nameValidity ) :: tail ->
                if name == "" then
                    tail

                else
                    ( name, value, nameValidity ) :: tail

    else
        list
            |> List.updateAt index
                (\( name, _, nameValidity ) ->
                    ( name, value, nameValidity )
                )


updateFromBackend : ToFrontend -> Model -> ( Model, Cmd FrontendMsg )
updateFromBackend msg model =
    case msg of
        NoOpToFrontend ->
            ( model, Cmd.none )

        OperationSuccessful ->
            ( { model | showDialog = Nothing }
            , if model.nameValidity == Complete then
                Lamdera.sendToBackend (RequestUserGroupsAndAccounts model.user)

              else
                Cmd.none
            )

        NameAlreadyExists name ->
            case model.showDialog of
                Just (AddPersonDialog dialogModel) ->
                    if dialogModel.name == name then
                        -- we reset submitted to False because this can be
                        -- an error message we get from the backend in case
                        -- of a race creating this person
                        ( { model
                            | showDialog =
                                Just
                                    (AddPersonDialog
                                        { dialogModel
                                            | nameInvalid = True
                                            , submitted = False
                                        }
                                    )
                          }
                        , Cmd.none
                        )

                    else
                        ( model, Cmd.none )

                Just (AddAccountOrGroupDialog dialogModel) ->
                    if dialogModel.name == name then
                        -- we reset submitted to False because this can be
                        -- an error message we get from the backend in case
                        -- of a race creating this group or account
                        ( { model
                            | showDialog =
                                Just
                                    (AddAccountOrGroupDialog
                                        { dialogModel
                                            | nameInvalid = True
                                            , submitted = False
                                        }
                                    )
                          }
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
                                                |> markInvalidPrefix prefix
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    ( if String.startsWith prefix model.user then
                        { model | nameValidity = InvalidPrefix }

                      else
                        model
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AutocompletePersonPrefix response ->
            case model.showDialog of
                Just (AddAccountOrGroupDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddAccountOrGroupDialog
                                    { dialogModel
                                        | ownersOrMembers =
                                            dialogModel.ownersOrMembers
                                                |> completeToLongestCommonPrefix response
                                    }
                                )
                      }
                    , Cmd.none
                    )

                Nothing ->
                    if
                        String.startsWith response.prefix model.user
                            && String.startsWith model.user response.longestCommonPrefix
                    then
                        ( { model
                            | user = response.longestCommonPrefix
                            , nameValidity =
                                if response.complete then
                                    Complete

                                else
                                    Incomplete
                          }
                        , Lamdera.sendToBackend
                            (RequestUserGroupsAndAccounts response.longestCommonPrefix)
                        )

                    else
                        ( model, Cmd.none )

                _ ->
                    ( model, Cmd.none )

        InvalidGroupPrefix prefix ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> markInvalidPrefix prefix
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AutocompleteGroupPrefix response ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | groupSpendings =
                                            dialogModel.groupSpendings
                                                |> completeToLongestCommonPrefix response
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        InvalidAccountPrefix prefix ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> markInvalidPrefix prefix
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        AutocompleteAccountPrefix response ->
            case model.showDialog of
                Just (AddSpendingDialog dialogModel) ->
                    ( { model
                        | showDialog =
                            Just
                                (AddSpendingDialog
                                    { dialogModel
                                        | transactions =
                                            dialogModel.transactions
                                                |> completeToLongestCommonPrefix response
                                    }
                                )
                      }
                    , Cmd.none
                    )

                _ ->
                    ( model, Cmd.none )

        ListUserGroupsAndAccounts { user, groups, accounts } ->
            ( if model.user == user then
                { model
                    | userGroupsAndAccounts = Just ( groups, accounts )
                }

              else
                model
            , Cmd.none
            )


markInvalidPrefix prefix list =
    list
        |> List.map
            (\( name, value, nameValidity ) ->
                if String.startsWith prefix name then
                    ( name, value, InvalidPrefix )

                else
                    ( name, value, nameValidity )
            )


completeToLongestCommonPrefix { prefix, longestCommonPrefix, complete } list =
    list
        |> List.map
            (\( name, value, nameValidity ) ->
                if
                    String.startsWith prefix name
                        && String.startsWith name longestCommonPrefix
                then
                    ( longestCommonPrefix
                    , value
                    , if complete then
                        Complete

                      else
                        Incomplete
                    )

                else
                    ( name, value, nameValidity )
            )


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
                                    (canSubmitPerson dialogModel)

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
                                    (canSubmitAccountOrGroup dialogModel)

                            AddSpendingDialog dialogModel ->
                                config "Add Spending"
                                    (addSpendingInputs dialogModel)
                                    (canSubmitSpending dialogModel)
                    )

        userAttributes =
            case model.nameValidity of
                InvalidPrefix ->
                    [ Background.color red ]

                _ ->
                    []
    in
    { title = "Accounting"
    , body =
        -- Elm UI body
        [ layout
            [ inFront (Dialog.view dialogConfig)
            ]
            (column [ width fill, spacing 20, padding 20 ]
                ([ row [ centerX, spacing 70, padding 20 ]
                    [ Input.button greenButtonStyle
                        { label = text "Add Person"
                        , onPress = Just ShowAddPersonDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Account"
                        , onPress = Just ShowAddAccountDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Group"
                        , onPress = Just ShowAddGroupDialog
                        }
                    , Input.button greenButtonStyle
                        { label = text "Add Spending"
                        , onPress = Just ShowAddSpendingDialog
                        }
                    ]
                 , Input.text userAttributes
                    { label = Input.labelLeft [] (text "Your name:")
                    , placeholder = Nothing
                    , onChange = UpdateName
                    , text = model.user
                    }
                 ]
                    ++ (case model.userGroupsAndAccounts of
                            Just ( groups, accounts ) ->
                                [ column [ spacing 10, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
                                    [ text "Your Groups"
                                    , viewGroupsOrAccounts model.user groups
                                    ]
                                , column [ spacing 10, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
                                    [ text "Your Accounts"
                                    , viewGroupsOrAccounts model.user accounts
                                    ]
                                , column [ spacing 10, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
                                    [ text "Amounts due"
                                    , personalAmountsDue groups accounts
                                        |> Dict.toList
                                        |> viewAmountsDue
                                    ]
                                ]

                            _ ->
                                []
                       )
                )
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
        ++ listInputs
            label
            "Share"
            AddOwnerOrMemberName
            UpdateOwnerOrMemberName
            UpdateOwnerOrMemberShare
            ownersOrMembers


addSpendingInputs { description, date, dateText, datePickerModel, totalSpending, groupSpendings, transactions } =
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
            ++ listInputs
                "Group"
                "Amount"
                AddGroupName
                UpdateGroupName
                UpdateGroupAmount
                groupSpendings
        )
    , column [ spacing 20, Background.color (rgb 0.9 0.9 0.9), padding 20 ]
        ([ text "Transactions" ]
            ++ listInputs
                "Account"
                "Amount"
                AddAccountName
                UpdateAccountName
                UpdateAccountAmount
                transactions
        )
    ]


listInputs nameLabel valueLabel addMsg updateNameMsg updateValueMsg items =
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
                , onChange = addMsg
                , text = ""
                }
            , Input.text []
                { label = Input.labelLeft [] (text valueLabel)
                , placeholder = Nothing
                , onChange = \_ -> NoOpFrontendMsg
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
                        , onChange = updateNameMsg index
                        , text = name
                        }
                    , Input.text []
                        { label = Input.labelLeft [] (text valueLabel)
                        , placeholder = Nothing
                        , onChange = updateValueMsg index
                        , text = value
                        }
                    ]
            )
            items
        |> List.reverse


canSubmitPerson { name, nameInvalid, submitted } =
    not submitted && not nameInvalid && String.length name > 0


canSubmitAccountOrGroup { name, nameInvalid, ownersOrMembers, submitted } =
    not submitted
        && not nameInvalid
        && String.length name
        > 0
        && (ownersOrMembers
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


canSubmitSpending { description, date, totalSpending, groupSpendings, transactions, submitted } =
    not submitted
        && Maybe.isJust date
        && String.length description
        > 0
        && (totalSpending
                |> parseAmountValue
                |> Maybe.andThen
                    (\totalSpendingInt ->
                        Maybe.combine
                            [ groupSpendings
                                |> List.map
                                    (\( _, amount, nameValidity ) ->
                                        case nameValidity of
                                            Complete ->
                                                parseAmountValue amount

                                            _ ->
                                                Nothing
                                    )
                                |> Maybe.combine
                                |> Maybe.map List.sum
                                |> Maybe.map ((==) totalSpendingInt)
                            , transactions
                                |> List.map
                                    (\( _, amount, nameValidity ) ->
                                        case nameValidity of
                                            Complete ->
                                                parseAmountValue amount

                                            _ ->
                                                Nothing
                                    )
                                |> Maybe.combine
                                |> Maybe.map List.sum
                                |> Maybe.map ((==) totalSpendingInt)
                            ]
                    )
                |> Maybe.map (List.all identity)
                |> Maybe.withDefault False
           )


viewGroupsOrAccounts user list =
    let
        preprocessedList =
            list
                |> List.map
                    (\( name, shares, Amount totalAmount ) ->
                        let
                            userShare =
                                Dict.get user shares
                                    |> Maybe.map (\(Share share) -> share)
                                    |> Maybe.withDefault 0

                            totalShares =
                                Dict.values shares
                                    |> List.map (\(Share share) -> share)
                                    |> List.sum

                            userAmount =
                                totalAmount * userShare // totalShares
                        in
                        { name = name
                        , share =
                            String.fromInt userShare
                                ++ " out of "
                                ++ String.fromInt totalShares
                        , totalAmount = viewAmount totalAmount
                        , userAmount = userAmount
                        }
                    )

        total =
            preprocessedList
                |> List.map .userAmount
                |> List.sum
                |> (\totalUserAmount ->
                        [ { name = "Total"
                          , share = ""
                          , totalAmount = ""
                          , userAmount = totalUserAmount
                          }
                        ]
                   )
    in
    table [ Border.solid, Border.width 1, padding 20, spacing 30 ]
        { data = preprocessedList ++ total
        , columns =
            [ { header = text "Name"
              , width = fill
              , view = .name >> text
              }
            , { header = text "Your share"
              , width = fill
              , view = .share >> text
              }
            , { header = text "Total spending"
              , width = fill
              , view = .totalAmount >> text
              }
            , { header = text "Your spending"
              , width = fill
              , view = .userAmount >> viewAmount >> text
              }
            ]
        }


viewAmountsDue data =
    table [ Border.solid, Border.width 1, padding 20, spacing 30 ]
        { data = data
        , columns =
            [ { header = text "Name"
              , width = fill
              , view = first >> text
              }
            , { header = text "Due"
              , width = fill
              , view =
                    second
                        >> (\(Amount value) -> max 0 value)
                        >> viewAmount
                        >> text
              }
            , { header = text "Owed"
              , width = fill
              , view =
                    second
                        >> (\(Amount value) -> min 0 value)
                        >> negate
                        >> viewAmount
                        >> text
              }
            ]
        }


viewAmount amount =
    let
        sign =
            if amount < 0 then
                "-"

            else
                ""

        absAmount =
            abs amount
    in
    remainderBy 100 absAmount
        |> String.fromInt
        |> String.padLeft 2 '0'
        |> (++) "."
        |> (++) (absAmount // 100 |> String.fromInt)
        |> (++) sign


parseAmountValue : String -> Maybe Int
parseAmountValue amount =
    case
        Regex.fromString "^(\\-?)([0-9]*)[.,]?([0-9]*)$"
            |> Maybe.withDefault Regex.never
            |> flip Regex.find amount
            |> List.map .submatches
    of
        [ [ Nothing, Just integer, Nothing ] ] ->
            String.toInt integer
                |> Maybe.map ((*) 100)

        [ [ Just "-", Just integer, Nothing ] ] ->
            String.toInt integer
                |> Maybe.map ((*) -100)

        [ [ Nothing, Nothing, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt decimal
                        |> Maybe.map ((*) 10)

                2 ->
                    String.toInt decimal

                _ ->
                    Nothing

        [ [ Just "-", Nothing, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt decimal
                        |> Maybe.map ((*) -10)

                2 ->
                    String.toInt decimal
                        |> Maybe.map negate

                _ ->
                    Nothing

        [ [ Nothing, Just integer, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((*) 10)
                                    |> Maybe.map ((+) integerValue)
                            )

                2 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((+) integerValue)
                            )

                _ ->
                    Nothing

        [ [ Just "-", Just integer, Just decimal ] ] ->
            case String.length decimal of
                1 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((*) 10)
                                    |> Maybe.map ((+) integerValue)
                            )
                        |> Maybe.map negate

                2 ->
                    String.toInt integer
                        |> Maybe.map ((*) 100)
                        |> Maybe.andThen
                            (\integerValue ->
                                String.toInt decimal
                                    |> Maybe.map ((+) integerValue)
                            )
                        |> Maybe.map negate

                _ ->
                    Nothing

        _ ->
            Nothing


personalAmounts : List ( String, Dict String Share, Amount ) -> Dict String Amount
personalAmounts list =
    list
        |> List.map
            (\( _, shares, Amount totalAmount ) ->
                let
                    totalShares =
                        Dict.values shares
                            |> List.map (\(Share share) -> share)
                            |> List.sum
                in
                Dict.map
                    (\_ (Share share) ->
                        Amount (totalAmount * share // totalShares)
                    )
                    shares
            )
        |> List.foldl addAmounts Dict.empty


personalAmountsDue : List ( String, Group, Amount ) -> List ( String, Account, Amount ) -> Dict String Amount
personalAmountsDue groupSpendings transactions =
    let
        groupAmounts =
            personalAmounts groupSpendings

        transactionAmounts =
            personalAmounts transactions
                |> Dict.map (\_ (Amount amount) -> Amount -amount)
    in
    addAmounts groupAmounts transactionAmounts
