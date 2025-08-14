#!/usr/bin/python
# coding=utf-8
'''
Created on Sep 01, 2017

@author: tao@fit2cloud.com
'''

import argparse
import commands

class AppAdm(object):

    def __init__(self):
        usage = '''
    appadm <command> [<args>]
命令:
    deploy --code-dir
    stop --code-dir
    beforeInstall --code-dir
    install --code-dir
    afterInstall --code-dir
    start --code-dir
    validateService --code-dir
例子: 
    appadm deploy --code-dir=/tmp/
'''
        
        parser = argparse.ArgumentParser(formatter_class=argparse.RawTextHelpFormatter,
                                     #description=textwrap.dedent(description),
                                     #epilog=textwrap.dedent(epilog),
                                     usage=usage
                                     )
        parser.add_argument('command', metavar='command', help='命令, deploy')
        parser.add_argument('-v', '--version', action='version', version='0.1')
        # parse_args defaults to [1:] for args, but you need to
        # exclude the rest of the args too, or validation will fail
        args = parser.parse_args(sys.argv[1:2])
        if not hasattr(self, args.command):
            print '错误: 不支持该命令: %s' % args.command
            parser.print_help()
            print '错误: 不支持该命令: %s' % args.command
            exit(1)
        # use dispatch pattern to invoke method with same name
        getattr(self, args.command)(args)
        
    def deploy(self, argv):
        #appadm deploy --file-path=/Users/tao/Desktop/ci-demo-app-1.0-293.zip --host-ip=try.fit2cloud.com --ssh-port=22 --ssh-password=xxxxxx
        parser = argparse.ArgumentParser(description='部署CodeDeploy规范包')
        arg = parser.add_argument
        arg('--code-dir', nargs='?', const=True, default="", metavar='code dir path', help='-f, --code-dir is optional, default execution dir', required=False)
        args = parser.parse_args(sys.argv[2:])
        
        codeDirPath = args.code_dir
        if(codeDirPath == "") :
            codeDirPath = os.getcwd()
            #print "codeDirPath=%s" % codeDirPath
            pass


        codeDeployer = CodeDeployer(codeDirPath)

        print "--------------------------------------"
        exitcode, output = commands.getstatusoutput("/usr/bin/chmod -R a+rwx %s" % codeDirPath)
        print "chmodPathOutput=%s\n" % output
        if exitcode!=0:
            raise Exception("Deploy Error! Step：chmodPath")
        print "--------------------------------------"
        exitcode, stopOutput = codeDeployer.stop()
        print "stopOutput=%s\n" % stopOutput
        if exitcode!=0:
            raise Exception("Deploy Error! Step：stop")
        print "--------------------------------------"
        exitcode, beforeInstallOutput = codeDeployer.beforeInstall()
        print "beforeInstallOutput=%s\n" % beforeInstallOutput
        if exitcode!=0:
            raise Exception("Deploy Error! Step：BeforeInstall")
        print "--------------------------------------"
        installOutput = codeDeployer.install()
        print "installOutput=%s\n" % installOutput
        if exitcode!=0:
            raise Exception("Deploy Error! Step：Install")
        print "--------------------------------------"
        exitcode, afterInstallOutput = codeDeployer.afterInstall()
        print "afterInstallOutput=%s\n" % afterInstallOutput
        if exitcode!=0:
            raise Exception("Deploy Error! Step：AfterInstall")
        print "--------------------------------------"
        exitcode, startOutput = codeDeployer.start()
        print "startOutput=%s\n" % startOutput
        if exitcode!=0:
            raise Exception("Deploy Error! Step：Start")
        print "--------------------------------------"
        exitcode, validateOutput = codeDeployer.validateService()
        print "validateOutput=%s\n" % validateOutput
        if exitcode!=0:
            raise Exception("Deploy Error! Step:ValidateService")
        pass
    
    def stop(self, argv):
        #appadm deploy --file-path=/Users/tao/Desktop/ci-demo-app-1.0-293.zip --host-ip=try.fit2cloud.com --ssh-port=22 --ssh-password=xxxxxx
        parser = argparse.ArgumentParser(description='部署CodeDeploy规范包')
        arg = parser.add_argument
        arg('--code-dir', nargs='?', const=True, default="", metavar='code dir path', help='-f, --code-dir is optional, default execution dir', required=False)
        args = parser.parse_args(sys.argv[2:])
        
        codeDirPath = args.code_dir 
        if(codeDirPath == "") :
            codeDirPath = os.getcwd()
            #print "codeDirPath=%s" % codeDirPath
            pass
        
        codeDeployer = CodeDeployer(codeDirPath)
        print "--------------------------------------"
        exitcode, stopOutput = codeDeployer.stop()
        print "stopOutput=\n%s" % stopOutput
    
    def beforeInstall(self, argv):
        #appadm deploy --file-path=/Users/tao/Desktop/ci-demo-app-1.0-293.zip --host-ip=try.fit2cloud.com --ssh-port=22 --ssh-password=xxxxxx
        parser = argparse.ArgumentParser(description='部署CodeDeploy规范包')
        arg = parser.add_argument
        arg('--code-dir', nargs='?', const=True, default="", metavar='code dir path', help='-f, --code-dir is optional, default execution dir', required=False)
        args = parser.parse_args(sys.argv[2:])
        
        codeDirPath = args.code_dir 
        if(codeDirPath == "") :
            codeDirPath = os.getcwd()
            #print "codeDirPath=%s" % codeDirPath
            pass
        
        codeDeployer = CodeDeployer(codeDirPath)
        print "--------------------------------------"
        exitcode, beforeInstallOutput = codeDeployer.beforeInstall()
        print "beforeInstallOutput=\n%s" % beforeInstallOutput
    
    def install(self, argv):
        #appadm deploy --file-path=/Users/tao/Desktop/ci-demo-app-1.0-293.zip --host-ip=try.fit2cloud.com --ssh-port=22 --ssh-password=xxxxxx
        parser = argparse.ArgumentParser(description='部署CodeDeploy规范包')
        arg = parser.add_argument
        arg('--code-dir', nargs='?', const=True, default="", metavar='code dir path', help='-f, --code-dir is optional, default execution dir', required=False)
        args = parser.parse_args(sys.argv[2:])
        
        codeDirPath = args.code_dir 
        if(codeDirPath == "") :
            codeDirPath = os.getcwd()
            #print "codeDirPath=%s" % codeDirPath
            pass
        
        codeDeployer = CodeDeployer(codeDirPath)
        print "--------------------------------------"
        installOutput = codeDeployer.install()
        if(installOutput!=None and installOutput!="") :
            print "installOutput=%s" % installOutput
    
    def afterInstall(self, argv):
        #appadm deploy --file-path=/Users/tao/Desktop/ci-demo-app-1.0-293.zip --host-ip=try.fit2cloud.com --ssh-port=22 --ssh-password=xxxxxx
        parser = argparse.ArgumentParser(description='部署CodeDeploy规范包')
        arg = parser.add_argument
        arg('--code-dir', nargs='?', const=True, default="", metavar='code dir path', help='-f, --code-dir is optional, default execution dir', required=False)
        args = parser.parse_args(sys.argv[2:])
        
        codeDirPath = args.code_dir 
        if(codeDirPath == "") :
            codeDirPath = os.getcwd()
            #print "codeDirPath=%s" % codeDirPath
            pass
        
        codeDeployer = CodeDeployer(codeDirPath)
        print "--------------------------------------"
        exitcode, afterInstallOutput = codeDeployer.afterInstall()
        print "afterInstallOutput=\n%s" % afterInstallOutput
    
    def start(self, argv):
        #appadm deploy --file-path=/Users/tao/Desktop/ci-demo-app-1.0-293.zip --host-ip=try.fit2cloud.com --ssh-port=22 --ssh-password=xxxxxx
        parser = argparse.ArgumentParser(description='部署CodeDeploy规范包')
        arg = parser.add_argument
        arg('--code-dir', nargs='?', const=True, default="", metavar='code dir path', help='-f, --code-dir is optional, default execution dir', required=False)
        args = parser.parse_args(sys.argv[2:])
        
        codeDirPath = args.code_dir 
        if(codeDirPath == "") :
            codeDirPath = os.getcwd()
            #print "codeDirPath=%s" % codeDirPath
            pass
        
        codeDeployer = CodeDeployer(codeDirPath)
        print "--------------------------------------"
        exitcode, startOutput = codeDeployer.start()
        print "startOutput=\n%s" % startOutput
    
    def validateService(self, argv):
        #appadm deploy --file-path=/Users/tao/Desktop/ci-demo-app-1.0-293.zip --host-ip=try.fit2cloud.com --ssh-port=22 --ssh-password=xxxxxx
        parser = argparse.ArgumentParser(description='部署CodeDeploy规范包')
        arg = parser.add_argument
        arg('--code-dir', nargs='?', const=True, default="", metavar='code dir path', help='-f, --code-dir is optional, default execution dir', required=False)
        args = parser.parse_args(sys.argv[2:])
        
        codeDirPath = args.code_dir 
        if(codeDirPath == "") :
            codeDirPath = os.getcwd()
            #print "codeDirPath=%s" % codeDirPath
            pass
        
        codeDeployer = CodeDeployer(codeDirPath)
        print "--------------------------------------"
        exitcode, validateOutput = codeDeployer.validateService()
        print "validateOutput=\n%s" % validateOutput
        
  
import paramiko
import os,sys,time

class AppSpec(object):
    '''
    classdocs
    '''


    def __init__(self):
        '''
        Constructor
        '''
        pass
    
    def setInstallSourceDestMappings(self, installSourceDestMappings):
        self.installSourceDestMappings = installSourceDestMappings
    
    def getInstallSourceDestMappings(self):
        return self.installSourceDestMappings
    
    def getPermissions(self):
        return self.permissions
    
    def setPermissions(self, permissions):
        self.permissions = permissions
    
    def setBeforeInstallScriptTasks(self, beforeInstallScriptTasks):
        self.beforeInstallScriptTasks = beforeInstallScriptTasks
    
    def getBeforeInstallScriptTasks(self):
        return self.beforeInstallScriptTasks
    
    def setAfterInstallScriptTasks(self, afterInstallScriptTasks):
        self.afterInstallScriptTasks = afterInstallScriptTasks
    
    def getAfterInstallScriptTasks(self):
        return self.afterInstallScriptTasks
    
    def setApplicationStopScriptTasks(self, applicationStopScriptTasks):
        self.applicationStopScriptTasks = applicationStopScriptTasks
    
    def getApplicationStopScriptTasks(self):
        return self.applicationStopScriptTasks
    
    def setApplicationStartScriptTasks(self, applicationStartScriptTasks):
        self.applicationStartScriptTasks = applicationStartScriptTasks
    
    def getApplicationStartScriptTasks(self):
        return self.applicationStartScriptTasks
    
    def setValidateServiceScriptTasks(self, validateServiceScriptTasks):
        self.validateServiceScriptTasks = validateServiceScriptTasks
    
    def getValidateServiceScriptTasks(self):
        return self.validateServiceScriptTasks

import json

class ScriptTask(object):
    '''
    classdocs
    '''

    def __init__(self):
        '''
        Constructor
        '''
        self.scriptPath = None
        self.timeout = None
        self.runas = None
        pass
        
    def setScriptPath(self, scriptPath):
        self.scriptPath = scriptPath
    
    def setTimeout(self, timeout):
        self.timeout = timeout
    
    def setRunAs(self, runas):
        self.runas = runas
        
    def getScriptPath(self):
        return self.scriptPath
    
    def getTimeout(self):
        return self.timeout
    
    def getRunAs(self):
        return self.runas
        
    def toJSON(self):
        dictScriptTask = self.toDict()
        jsonScriptTask = json.dumps(dictScriptTask, indent=2)
        return jsonScriptTask
    
    def toDict(self):
        dictScriptTask = {}
        dictScriptTask['location'] = self.scriptPath
        dictScriptTask['timeout'] = self.timeout
        dictScriptTask['runas'] = self.runas
        return dictScriptTask

import json

class Permission(object):
    '''
    classdocs
    '''


    def __init__(self):
        '''
        Constructor
        '''
        pass
    
    def getTargetObject(self):
        return self.targetObject
    
    def setTargetObject(self, targetObject):
        self.targetObject = targetObject
        
    def getPattern(self):
        return self.pattern
    
    def setPattern(self, pattern):
        self.pattern = pattern
    
    def getExceptFiles(self):
        return self.exceptFiles
    
    def setExceptFiles(self, exceptFiles):
        self.exceptFiles = exceptFiles
    
    def getOwner(self):
        return self.owner
    
    def setOwner(self, owner):
        self.owner = owner
        
    def getGroup(self):
        return self.group
    
    def setGroup(self, group):
        self.group = group
        
    def getMode(self):
        return self.mode
    
    def setMode(self, mode):
        self.mode = mode
    
    def getAcls(self):
        return self.acls
    
    def setAcls(self, acls):
        self.acls = acls
    
    def getTargetTypes(self):
        return self.targetTypes
    
    def setTargetTypes(self, targetTypes):
        self.targetTypes = targetTypes
    
    def toJson(self):
        permissionDict={}
        permissionDict['object'] = self.targetObject
        permissionDict['pattern'] = self.pattern
        permissionDict['except'] = self.exceptFiles
        permissionDict['owner'] = self.owner
        permissionDict['group'] = self.group
        permissionDict['mode'] = self.mode
        permissionDict['acls'] = self.acls
        permissionDict['type'] = self.targetTypes
        jsonPermission = json.dumps(permissionDict, indent=2)
        return jsonPermission
    
    @staticmethod
    def fromDict(permissionDict):
        permission = Permission()
        targetObject = None
        if(permissionDict.has_key('object')) :
            targetObject = permissionDict['object']
        pattern = None
        if(permissionDict.has_key('pattern')) :
            pattern = permissionDict['pattern']
        owner = None
        exceptFiles = None
        if(permissionDict.has_key('except')) :
            exceptFiles = permissionDict['except']
        if(permissionDict.has_key('owner')) :
            owner = permissionDict['owner']
        group = None
        if(permissionDict.has_key('group')) :
            group = permissionDict['group']
        mode = None
        if(permissionDict.has_key('mode')) :
            mode = permissionDict['mode']
        acls = None
        if(permissionDict.has_key('acls')) :
            acls = permissionDict['acls']
        targetTypes = None
        if(permissionDict.has_key('type')) :
            targetTypes = permissionDict['type']
        
        permission.setTargetObject(targetObject)
        permission.setPattern(pattern)
        permission.setExceptFiles(exceptFiles)
        permission.setOwner(owner)
        permission.setGroup(group)
        permission.setMode(mode)
        permission.setAcls(acls)
        permission.setTargetTypes(targetTypes)
        return permission

import traceback
import yaml 
import os
import types
import logging
logger = logging.getLogger(__name__)

class AppSpecDAO(object):
    '''
    classdocs
    '''


    def __init__(self):
        '''
        Constructor
        '''
        pass
    
    @staticmethod
    def validateAppSpec(appSpecYamlPath):
        listErrors=[]
        if(os.path.exists(appSpecYamlPath)) :
            #Validate AppSpec
            dataMap = None
            try:
                f = open(appSpecYamlPath)  
                dataMap = yaml.load(f)
            except Exception, e :
                logger.error(e)

            installSourceDestMappings=None
            try:
                if(dataMap.has_key('files')) :
                    installSourceDestDict = dataMap['files']
                    installSourceDestMappings=installSourceDestDict
                    if installSourceDestMappings!=None and len(installSourceDestMappings)>0 :
                        isSourceDestMappingInfoValid = True
                        logger.info(installSourceDestMappings)
                        for installSourceDestMapping in installSourceDestMappings:
                            if type(installSourceDestMapping) is types.DictType :
                                if not installSourceDestMapping.has_key('destination') or not installSourceDestMapping.has_key('source') :
                                    isSourceDestMappingInfoValid = False
                                if isSourceDestMappingInfoValid == False :
                                    listErrors.append("错误: 部署源文件目录及目标文件目录配置有问题，请检查输入字符串或特殊字符，建议手动重新输入！")
                            else :
                                listErrors.append("错误: files部分配置有误，常见导致错误的原因是source或destination后冒号后无空格，请检查并修改!") 
                                listErrors.append("如source:/ 应改为source: /")
                                listErrors.append("如destination:/xxx/yyy/zzz 应改为destination: /xxx/yyy/zzz")
                                pass
                        pass
                else :
                    listErrors.append("错误: 部署源文件目录及目标文件目录没有设置！")
            except Exception, e :
                listErrors.append("错误: appspec.yml格式有问题，不符合yaml文件规范！请基于示例配置文件基础上修改，参考https://github.com/fit2cloud/f2c-codedeploy-demo/blob/master/appspec.yml")
                logger.error(e)
                
            try:
                if(dataMap.has_key('hooks')) :
                    hooksDict = dataMap['hooks']
                    actions = ['ApplicationStop', 'BeforeInstall', 'AfterInstall', 'AfterInstall', 'ApplicationStart', 'ValidateService']
                    for action in actions :
                        if(hooksDict.has_key(action)) :
                            actionScriptsDicts = dataMap['hooks'][action]
                            if actionScriptsDicts!=None and len(actionScriptsDicts) > 0 :
                                for actionScriptsDict in actionScriptsDicts :
                                    if type(actionScriptsDict) is types.DictType :
                                        scriptTask = ScriptTask()
                                        if actionScriptsDict.has_key('location') :
                                            scriptPath = actionScriptsDict['location']
                                            scriptTask.setScriptPath(scriptPath)
                                        if actionScriptsDict.has_key('timeout') :
                                            scriptTask.setTimeout(actionScriptsDict['timeout'])
                                        if actionScriptsDict.has_key('runas') :
                                            scriptTask.setRunAs(actionScriptsDict['runas'])
                                    else :
                                        listErrors.append("错误: %s 部分配置有误, 冒号后需要有空格，如location:scripts/xxx.sh 应该为location: scripts/xxx.sh" % action)
                                        
            except Exception, e :
                logger.error(e)
        else :
            listErrors.append("错误: appspec.yml不存在!请确保源代码根目录包含该文件，遵循AWS Code Deploy规范!")
        
        return listErrors
        pass
        
    def getAppSpec(self, appSpecYamlPath):
        if(not os.path.exists(appSpecYamlPath)) :
            msg = "appspec.yml does not exist at %s" % appSpecYamlPath
            logger.error(msg)
            return None
        
        self.dataMap = None
        try:
            f = open(appSpecYamlPath)  
            self.dataMap = yaml.load(f)
        except Exception, e :
            logger.error(e)
        
        if(self.dataMap == None) :
            return None
            pass
        
        appSpec=AppSpec()
        installSourceDestMappings=None
        permissions = []
        try:
            if(self.dataMap.has_key('files')) :
                installSourceDestDict = self.dataMap['files']
                installSourceDestMappings=installSourceDestDict
        except Exception, e :
            logger.error(e)
        appSpec.setInstallSourceDestMappings(installSourceDestMappings)
        
        try:
            if(self.dataMap.has_key('permissions')) :
                permissionDicts = self.dataMap['permissions']
                if(permissionDicts!=None) :
                    for permissionDict in permissionDicts :
                        permission = Permission.fromDict(permissionDict)
                        permissions.append(permission)
                        pass
        except Exception, e :
            traceback.print_exc()
            logger.error(e)
        appSpec.setPermissions(permissions)
        
        beforeInstallScriptTasks=[]
        try:
            if(self.dataMap.has_key('hooks')) :
                hooksDict = self.dataMap['hooks']
                if(hooksDict.has_key('BeforeInstall')) :
                    beforeInstallScriptsDicts = self.dataMap['hooks']['BeforeInstall']
                    if beforeInstallScriptsDicts!=None and len(beforeInstallScriptsDicts) > 0 :
                        for beforeInstallScriptDict in beforeInstallScriptsDicts :
                            if type(beforeInstallScriptDict) is types.DictType :
                                scriptTask = ScriptTask()
                                if beforeInstallScriptDict.has_key('location') :
                                    scriptPath = beforeInstallScriptDict['location']
                                    scriptTask.setScriptPath(scriptPath)
                                if beforeInstallScriptDict.has_key('timeout') :
                                    scriptTask.setTimeout(beforeInstallScriptDict['timeout'])
                                if beforeInstallScriptDict.has_key('runas') :
                                    scriptTask.setRunAs(beforeInstallScriptDict['runas'])
                                beforeInstallScriptTasks.append(scriptTask)
        except Exception, e :
            logger.error(e)
        appSpec.setBeforeInstallScriptTasks(beforeInstallScriptTasks)
        
        afterInstallScriptTasks=[]
        try:
            if(self.dataMap.has_key('hooks')) :
                hooksDict = self.dataMap['hooks']
                if(hooksDict.has_key('AfterInstall')) :
                    afterInstallScriptsDicts = self.dataMap['hooks']['AfterInstall']
                    if afterInstallScriptsDicts!=None and len(afterInstallScriptsDicts) > 0 :
                        for afterInstallScriptDict in afterInstallScriptsDicts :
                            if type(afterInstallScriptDict) is types.DictType :
                                scriptTask = ScriptTask()
                                if afterInstallScriptDict.has_key('location') :
                                    scriptPath = afterInstallScriptDict['location']
                                    scriptTask.setScriptPath(scriptPath)
                                if afterInstallScriptDict.has_key('timeout') :
                                    scriptTask.setTimeout(afterInstallScriptDict['timeout'])
                                if afterInstallScriptDict.has_key('runas') :
                                    scriptTask.setRunAs(afterInstallScriptDict['runas'])
                                afterInstallScriptTasks.append(scriptTask)
        except Exception, e :
            logger.error(e)
        appSpec.setAfterInstallScriptTasks(afterInstallScriptTasks)
        
        applicationStartScriptTasks=[]
        try:
            if(self.dataMap.has_key('hooks')) :
                hooksDict = self.dataMap['hooks']
                if(hooksDict.has_key('ApplicationStart')) :
                    applicationStartScriptsDicts = self.dataMap['hooks']['ApplicationStart']
                    if applicationStartScriptsDicts!=None and len(applicationStartScriptsDicts) > 0 :
                        for applicationStartScriptDict in applicationStartScriptsDicts :
                            if type(applicationStartScriptDict) is types.DictType :
                                scriptTask = ScriptTask()
                                if applicationStartScriptDict.has_key('location') :
                                    scriptPath = applicationStartScriptDict['location']
                                    scriptTask.setScriptPath(scriptPath)
                                if applicationStartScriptDict.has_key('timeout') :
                                    scriptTask.setTimeout(applicationStartScriptDict['timeout'])
                                if applicationStartScriptDict.has_key('runas') :
                                    scriptTask.setRunAs(applicationStartScriptDict['runas'])
                                applicationStartScriptTasks.append(scriptTask)
        except Exception, e :
            logger.error(e)
        appSpec.setApplicationStartScriptTasks(applicationStartScriptTasks)
        
        applicationStopScriptTasks=[]
        try:
            if(self.dataMap.has_key('hooks')) :
                hooksDict = self.dataMap['hooks']
                if(hooksDict.has_key('ApplicationStop')) :
                    applicationStopScriptsDicts = self.dataMap['hooks']['ApplicationStop']
                    if applicationStopScriptsDicts!=None and len(applicationStopScriptsDicts) > 0 :
                        for applicationStopScriptDict in applicationStopScriptsDicts :
                            if type(applicationStopScriptDict) is types.DictType :
                                scriptTask = ScriptTask()
                                if applicationStopScriptDict.has_key('location') :
                                    scriptPath = applicationStopScriptDict['location']
                                    scriptTask.setScriptPath(scriptPath)
                                if applicationStopScriptDict.has_key('timeout') :
                                    scriptTask.setTimeout(applicationStopScriptDict['timeout'])
                                if applicationStopScriptDict.has_key('runas') :
                                    scriptTask.setRunAs(applicationStopScriptDict['runas'])
                                applicationStopScriptTasks.append(scriptTask)
        except Exception, e :
            logger.error(e)
        appSpec.setApplicationStopScriptTasks(applicationStopScriptTasks)
        
        validateServiceScriptTasks=[]
        try:
            if(self.dataMap.has_key('hooks')) :
                hooksDict = self.dataMap['hooks']
                if(hooksDict.has_key('ValidateService')) :
                    validateServiceScriptsDicts = self.dataMap['hooks']['ValidateService']
                    if validateServiceScriptsDicts!=None and len(validateServiceScriptsDicts) > 0 :
                        for validateServiceScriptDict in validateServiceScriptsDicts :
                            if type(validateServiceScriptDict) is types.DictType :
                                scriptTask = ScriptTask()
                                if validateServiceScriptDict.has_key('location') :
                                    scriptPath = validateServiceScriptDict['location']
                                    scriptTask.setScriptPath(scriptPath)
                                if validateServiceScriptDict.has_key('timeout') :
                                    scriptTask.setTimeout(validateServiceScriptDict['timeout'])
                                if validateServiceScriptDict.has_key('runas') :
                                    scriptTask.setRunAs(validateServiceScriptDict['runas'])
                                validateServiceScriptTasks.append(scriptTask)
        except Exception, e :
            #logger.error(e)
            pass
        appSpec.setValidateServiceScriptTasks(validateServiceScriptTasks)
        
        return appSpec

import os
import hashlib
import random
import filecmp
import sys
import logging
logger = logging.getLogger(__name__)

class FileUtil(object):
    '''
    classdocs
    '''


    def __init__(self):
        '''
        Constructor
        '''
    @staticmethod
    def readContent(file_path):
        config_file = file(file_path, 'r')
        file_content = ""
        file_lines = config_file.readlines();
        for line in file_lines :
            file_content = file_content + line
        config_file.close()
        return file_content
    
    @staticmethod
    def writeContent(file_path, content):
        dir_path = os.path.dirname(file_path)
        os.system("mkdir -p %s" % dir_path)
        try:
            config_file = file(file_path, 'w')
            config_file.write(content)
            config_file.close()
        except Exception, e:
            logger.error(e)
    
    @staticmethod
    def dos2unix(file_path):
        config_file = file(file_path, 'rU')
        file_content = ""
        file_lines = config_file.readlines();
        for line in file_lines :
            file_content = file_content + line
        config_file.close()
        
        FileUtil.writeContent(file_path, file_content)
        pass
    
import datetime

class CodeDeployer(object):
    '''
    classdocs
    '''


    def __init__(self, codeHome):
        '''
        Constructor
        '''
        self.codeHome = codeHome
        self.uuid = commands.getoutput('uuidgen')
        self.appSpec = None
        self.appSpecDAO = None
        self.appSpecYamlPath = None
        pass
    
    def validate(self):
        self.appSpecYamlPath="%s/appspec.yml" % self.codeHome
        listErrors = AppSpecDAO.validateAppSpec(self.appSpecYamlPath)
        if(listErrors!=None and len(listErrors)>0) :
            for strError in listErrors :
                print strError
            return False
        else :
            return True
    
    def getRunAs(self):
        if(self.validate() == False) :
            return
        appSpecDAO = AppSpecDAO()
        self.appSpec = appSpecDAO.getAppSpec(self.appSpecYamlPath)
        scriptTasks = self.appSpec.getApplicationStopScriptTasks()

        for scriptTask in scriptTasks :
            runas = scriptTask.getRunAs();
        pass
        if(runas==None or len(runas) < 1):
            runas = 'app'

        return runas

    def stop(self):
        if(self.validate() == False) :
            return
        appSpecDAO = AppSpecDAO()
        self.appSpec = appSpecDAO.getAppSpec(self.appSpecYamlPath)
        scriptTasks = self.appSpec.getApplicationStopScriptTasks()
        exitcode, output = self.executeHookScriptTasks("ApplicationStop", self.codeHome, scriptTasks)
        return exitcode, output
    
    def beforeInstall(self):
        if(self.validate() == False) :
            return
        appSpecDAO = AppSpecDAO()
        self.appSpec = appSpecDAO.getAppSpec(self.appSpecYamlPath)
        scriptTasks = self.appSpec.getBeforeInstallScriptTasks()
        exitcode, output = self.executeHookScriptTasks("BeforeInstall", self.codeHome, scriptTasks)
        return exitcode, output
    
    def install(self):
        #1. execut stop action
        runas = self.getRunAs();
        if(self.validate() == False) :
            return
        appSpecDAO = AppSpecDAO()
        self.appSpec = appSpecDAO.getAppSpec(self.appSpecYamlPath)
        installSourceDestMappings = self.appSpec.getInstallSourceDestMappings()
        result=""
        statusResult=0
        for installSourceDestMapping in installSourceDestMappings :
            sourcePath=installSourceDestMapping['source']
            cmd=""
            if(sourcePath.startswith("/")) :
                cmd= "sudo su - %s -c \"cp -Rf %s%s %s\"" % (runas,self.codeHome, installSourceDestMapping['source'], installSourceDestMapping['destination'])
            else :
                cmd= "sudo su - %s -c \"cp -Rf %s/%s %s\"" % (runas,self.codeHome, installSourceDestMapping['source'], installSourceDestMapping['destination'])
            print cmd
            status, output = commands.getstatusoutput(cmd)
            result+=output
            statusResult+=status
        
        #print "output=%s" % output
        return result
    
    def afterInstall(self):
        if(self.validate() == False) :
            return
        appSpecDAO = AppSpecDAO()
        self.appSpec = appSpecDAO.getAppSpec(self.appSpecYamlPath)
        scriptTasks = self.appSpec.getAfterInstallScriptTasks()
        exitcode, output = self.executeHookScriptTasks("AfterInstall", self.codeHome, scriptTasks)
        return exitcode, output
    
    def start(self):
        if(self.validate() == False) :
            return
        appSpecDAO = AppSpecDAO()
        self.appSpec = appSpecDAO.getAppSpec(self.appSpecYamlPath)
        scriptTasks = self.appSpec.getApplicationStartScriptTasks()
        exitcode, output = self.executeHookScriptTasks("ApplicationStart", self.codeHome, scriptTasks)
        return exitcode, output
    
    def validateService(self):
        if(self.validate() == False) :
            return
        appSpecDAO = AppSpecDAO()
        self.appSpec = appSpecDAO.getAppSpec(self.appSpecYamlPath)
        scriptTasks = self.appSpec.getValidateServiceScriptTasks()
        exitcode, output = self.executeHookScriptTasks("ValidateService", self.codeHome, scriptTasks)
        return exitcode, output
    
    def executeHookScriptTasks(self, hookName, codeHome, scriptTasks):
        exitcode=0
        messages=[]
        scriptNotExist = False
        if scriptTasks!=None and len(scriptTasks) > 0 :
            for scriptTask in scriptTasks :
                try:
                    scriptPath = scriptTask.getScriptPath()
                    if os.path.exists("%s/%s" % (codeHome, scriptPath)) :
                        strTime = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        messages.append("%s:开始执行%s" % (strTime, scriptTask.getScriptPath()))
                        output, exitcode = self.executeScriptTask(codeHome, scriptTask)
                        strTime = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                        messages.append("%s:结束执行%s" % (strTime, scriptTask.getScriptPath()))
                        messages.append("执行返回码: %s " % exitcode)
                        messages.append("执行输出")
                        messages.append(output)
                    else :
                        scriptNotExist = True
                        msg = "脚本%s不存在,请检查版本部署代码包中包含该脚本或appspec.yml中脚本相对路径配置与脚本包中所在相对路径一致!" % scriptPath
                        messages.append(msg)
                        pass
                except Exception, e:
                    logger.error(e)
                    exitcode=1
            pass
        else :
            messages.append("%s脚本没有在appspec.yml中定义, 没有脚本执行输出!" % hookName)
            pass
        
        if(scriptNotExist==True) :
            exitcode = 1
        
        responseMessage = ""
        if(messages!=None and len(messages) > 0) :
            responseMessage = "\n".join(messages)
        return exitcode, responseMessage
    
    def executeScriptTask(self, codeHome, scriptTask):
        scriptPath = scriptTask.getScriptPath()
        timeout = scriptTask.getTimeout()
        runas = scriptTask.getRunAs()
        if(runas==None or len(runas) < 1):
            runas = 'app'
        print 'runas %s\n' % runas
        scriptFilePath = "%s/%s" % (codeHome,scriptPath)
        FileUtil.dos2unix(scriptFilePath)
        status, output = commands.getstatusoutput("chmod +x %s" % scriptFilePath)
        exitcode, output = commands.getstatusoutput("sudo su - %s -c \"%s\"" % (runas, scriptFilePath))

        print 'exitcode %s' % exitcode
        return output, exitcode

if __name__ == '__main__':
    AppAdm()
    
