* Создал аккаунт на aws.amazon.com
* Настроил защиту root-аккаунта (с помощью MFA)
* Создал IAM-пользователя oleg-admin, настроил MFA, добавил AdministratorAccess и создал AccessKey 
* Установил AWS cli и настроил профиль через aws configure
* Ниже результат вывода команды aws sts get-caller-identity

{
    "UserId": "AIDAW4XLEAY5HPNTH63HF",
    "Account": "474013238842",
    "Arn": "arn:aws:iam::474013238842:user/oleg-admin"
}
